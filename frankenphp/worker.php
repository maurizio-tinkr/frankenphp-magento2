<?php
/**
 * FrankenPHP worker for Magento / Mage-OS storefront pages (experimental).
 *
 * Kept in memory between requests: PHP's loaded classes, the autoloader, the ObjectManager factory
 * (DI configuration), and the connections to the database and the cache, which hold no customer data.
 * Not kept: every other Magento object. Each request gets a brand-new ObjectManager, so no shared
 * instance (request, response, session, layout, registry, app state...) can carry one customer's data
 * into the next request. Static properties are not reset: that is the remaining risk, and what
 * tests/leak.sh looks for.
 */

declare(strict_types=1);

use Magento\Framework\App\Bootstrap;
use Magento\Framework\App\Http;
use Magento\Framework\ObjectManager\ObjectManager;
use Magento\Framework\ObjectManagerInterface;

require '/var/www/html/app/bootstrap.php';

/**
 * Magento's Bootstrap answers a fatal error with a 500 and exit(1). In a worker, exit() skips the
 * request's clean-up and kills the worker: answer the same way, without the exit.
 */
final class WorkerBootstrap extends Bootstrap
{
    protected function terminate(\Throwable $e)
    {
        try {
            $this->getObjectManager()->get(\Psr\Log\LoggerInterface::class)->critical($e);
        } catch (\Throwable) {
            error_log((string) $e);
        }
        if (!headers_sent()) {
            http_response_code(500);
            header('Content-Type: text/plain');
        }
        echo "An error has happened during application run. See exception log for details.\n";
    }
}

// PHP settings changed with ini_set() outlive the request in worker mode. The admin, for one, renames the
// session cookie. Restore every setting before each request: once a response is sent, PHP refuses to
// change the session ones.
$iniAtBoot = ini_get_all(null, false);
$restoreIni = static function () use ($iniAtBoot): void {
    foreach (ini_get_all(null, false) as $name => $value) {
        if (array_key_exists($name, $iniAtBoot) && $iniAtBoot[$name] !== $value) {
            ini_set($name, (string) $iniAtBoot[$name]);
        }
    }
};

$params = $_SERVER;
$objectManagerFactory = Bootstrap::createObjectManagerFactory(BP, $params);

// Services that only hold connections, shared by every request.
const LONG_LIVED = [
    \Magento\Framework\App\ResourceConnection::class,
    \Magento\Framework\App\Cache\Frontend\Pool::class,
    \Magento\Framework\App\Cache\Type\FrontendPool::class,
];
$root = Bootstrap::create(BP, $params, $objectManagerFactory)->getObjectManager();
$longLived = [];
foreach (LONG_LIVED as $type) {
    // Shared instances are stored under the resolved class (in production: the generated Interceptor).
    $resolved = \Closure::bind(fn () => $this->_config->getPreference($type), $root, ObjectManager::class)();
    $longLived[$resolved] = $root->get($type);
}

// A transaction a request left open must not swallow the next customer's writes.
$rollBackLeftovers = static function (\Magento\Framework\App\ResourceConnection $resource): void {
    $connections = \Closure::bind(fn () => $this->connections, $resource, \Magento\Framework\App\ResourceConnection::class)();
    foreach ($connections as $name => $connection) {
        if ($connection->getTransactionLevel() > 0) {
            error_log("worker.php: rolling back a transaction left open on connection '$name'");
            while ($connection->getTransactionLevel() > 0) {
                $connection->rollBack();
            }
        }
    }
};

// The ObjectManager keeps its shared instances in a protected property: change it from its own scope.
$addShared = static function (ObjectManagerInterface $objectManager, array $instances): void {
    \Closure::bind(function () use ($instances) {
        $this->_sharedInstances = $instances + $this->_sharedInstances;
    }, $objectManager, ObjectManager::class)();
};
$clearShared = static function (ObjectManagerInterface $objectManager): void {
    \Closure::bind(function () {
        $this->_sharedInstances = [];
    }, $objectManager, ObjectManager::class)();
};

// Magento registers [$session, 'writeClose'] as a shutdown function for every session it starts. Those
// callbacks live until the worker stops and would keep each request's session objects, and everything
// they reference, in memory. writeClose() uses no properties, so empty the session objects instead.
$emptySessions = static function (ObjectManagerInterface $objectManager): void {
    $instances = \Closure::bind(fn () => $this->_sharedInstances, $objectManager, ObjectManager::class)();
    foreach ($instances as $instance) {
        if (!$instance instanceof \Magento\Framework\Session\SessionManager) {
            continue;
        }
        for ($class = new \ReflectionClass($instance); $class; $class = $class->getParentClass()) {
            foreach ($class->getProperties() as $property) {
                if ($property->isStatic() || $property->getDeclaringClass()->getName() !== $class->getName()) {
                    continue;
                }
                $name = $property->getName();
                \Closure::bind(function () use ($name) {
                    unset($this->$name);
                }, $instance, $class->getName())();
            }
        }
    }
};

// Static state Magento leaves behind, which classic mode throws away with the process:
// - config XML objects, registered in Config\Base::$instances (Magento ships destroy() for it)
// - commit callbacks never run, kept in CallbackPool together with the request's objects
$resetStatics = static function (): void {
    \Magento\Framework\App\Config\Base::destroy();
    \Closure::bind(static function () {
        self::$commitCallbacks = [];
    }, null, \Magento\Framework\Model\CallbackPool::class)();
};

$resource = $root->get(\Magento\Framework\App\ResourceConnection::class);

$handler = static function () use (
    $objectManagerFactory,
    $resource,
    $rollBackLeftovers,
    $longLived,
    $addShared,
    $clearShared,
    $emptySessions,
    $restoreIni,
    $resetStatics
): void {
    $restoreIni();
    $autoloaders = spl_autoload_functions();
    // Not Bootstrap::create(): it adds Magento's paths to the autoloader again on every call.
    $bootstrap = new WorkerBootstrap($objectManagerFactory, BP, $_SERVER);
    $objectManager = $bootstrap->getObjectManager();
    $addShared($objectManager, $longLived);
    header('X-FrankenPHP-Worker: 1');

    try {
        $bootstrap->run($bootstrap->createApplication(Http::class));
    } finally {
        // Magento saves sessions in a shutdown function, which in worker mode only runs when the worker
        // stops: save it now.
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_write_close();
        }
        $_SESSION = [];
        $rollBackLeftovers($resource);
        // Let this request's objects be freed: nothing may still point at them.
        // Creating an ObjectManager registers one more code-generation autoloader, which holds it.
        foreach (spl_autoload_functions() as $autoloader) {
            if (!in_array($autoloader, $autoloaders, true)) {
                spl_autoload_unregister($autoloader);
            }
        }
        $emptySessions($objectManager);
        $clearShared($objectManager);
        $resetStatics();
    }
};

// A safety net for whatever else piles up: each worker restarts after this many requests. 0 = never.
$maxRequests = getenv('WORKER_MAX_REQUESTS');
$maxRequests = $maxRequests === false || $maxRequests === '' ? 500 : (int) $maxRequests;

for ($served = 0; !$maxRequests || $served < $maxRequests; ++$served) {
    $keepRunning = frankenphp_handle_request($handler);
    gc_collect_cycles();
    if (!$keepRunning) {
        break;
    }
}
