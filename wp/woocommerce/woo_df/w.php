

/**
 * WordPress database table prefix.
 *
 * You can have multiple installations in one database if you give each
 * a unique prefix. Only numbers, letters, and underscores please!
 *
 * At the installation time, database tables are created with the specified prefix.
 * Changing this value after WordPress is installed will make your site think
 * it has not been installed.
 *
 * @link https://developer.wordpress.org/advanced-administration/wordpress/wp-config/#table-prefix
 */
$table_prefix = 'wp_';

/**
 * For developers: WordPress debugging mode.
 *
 * Change this to true to enable the display of notices during development.
 * It is strongly recommended that plugin and theme developers use WP_DEBUG
 * in their development environments.
 *
 * For information on other constants that can be used for debugging,
 * visit the documentation.
 *
 * @link https://developer.wordpress.org/advanced-administration/debug/debug-wordpress/
 */
define( 'WP_DEBUG', false );

/* Add any custom values between this line and the "stop editing" line. */

$_SERVER['HTTPS'] = 'on'; define('FORCE_SSL_LOGIN', true); define('FORCE_SSL_ADMIN', true);


define('AUTOMATIC_UPDATER_DISABLED', true); // 禁用所有自动更新
define('WP_AUTO_UPDATE_CORE', false); // 禁用 WordPress 核心更新

/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}

// define('FORCE_SSL_ADMIN', true);
// if ($_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https') {
//     $_SERVER['HTTPS'] = 'on';
// }

/** Sets up WordPress vars and included files. */
require_once ABSPATH . 'wp-settings.php';
