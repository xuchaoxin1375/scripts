<?php
/**
 * The base configuration for WordPress
 *
 * The wp-config.php creation script uses this file during the installation.
 * You don't have to use the website, you can copy this file to "wp-config.php"
 * and fill in the values.
 *
 * This file contains the following configurations:
 *
 * * Database settings
 * * Secret keys
 * * Database table prefix
 * * ABSPATH
 *
 * @link https://developer.wordpress.org/advanced-administration/wordpress/wp-config/
 *
 * @package WordPress
 */

// ** Database settings - You can get this info from your web host ** //
/** The name of the database for WordPress */
define( 'DB_NAME', '1.de' );

/** Database username */
define( 'DB_USER', 'root' );

/** Database password */
define( 'DB_PASSWORD', '15a58524d3bd2e49' );

/** Database hostname */
define( 'DB_HOST', 'localhost' );

/** Database charset to use in creating database tables. */
define( 'DB_CHARSET', 'utf8mb4' );

/** The database collate type. Don't change this if in doubt. */
define( 'DB_COLLATE', '' );

/**#@+
 * Authentication unique keys and salts.
 *
 * Change these to different unique phrases! You can generate these using
 * the {@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}.
 *
 * You can change these at any point in time to invalidate all existing cookies.
 * This will force all users to have to log in again.
 *
 * @since 2.6.0
 */
define( 'AUTH_KEY',         '6&Eal{4nH6MYZw$874$K|Dt*F7QW7QxVtV~zmNM}6w;)ZiOe%;Hr C/mD|tVuFjF' );
define( 'SECURE_AUTH_KEY',  '3K2SX1E1cn+08kMa8f-Q&j.~6u2j*zvmI]a7t99oJq<n,93qJ.Z9~OukSIy>$%O[' );
define( 'LOGGED_IN_KEY',    '~3.j5[#?!`N:GUhgqn$[!d5(D$P^z7_}s*+fP9]H>f<Y!(R#Ev9#/fhZzM8=y,B8' );
define( 'NONCE_KEY',        'Cbk=_,tsnT71RGa%[elxaphIp=tJ+kEB6Wj^LxPK0%Ue@#>%AL^9v%REr!k U+%0' );
define( 'AUTH_SALT',        'U12pD1fN^Xx*f!Qh$KSViAEbJJB1Jl#{.r9`T&xV3y }.PVzyU>us8Gw})Wc|7}k' );
define( 'SECURE_AUTH_SALT', 'iI0Wp,}XN!+8%`_T-#Mlb1tbE8yln7VgNf#I#5-=5,qA5#D6Hex}m_-N?eEfg9pP' );
define( 'LOGGED_IN_SALT',   'qZHPI2oP{t Vd=hUh:TUq6W~zwwt&yT8tYlp@B:_== (d?4rrJpaltdjY}z S)s#' );
define( 'NONCE_SALT',       'EFs_=,U*E@-I!e<w{o!8ew?}_7F?,jm/M$<QDU8I/f+CxmOrG@o?15F,*odo/K9n' );

/**#@-*/

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

define('DISABLE_WP_CRON', true);#禁用wp-cron任务,使用系统定时任务代替 

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
