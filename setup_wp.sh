#!/bin/bash

#Updating php sources
    sudo add-apt-repository ppa:ondrej/php -y
    sudo apt-get update

    # make sure system does automatic updates and fail2ban
    export DEBIAN_FRONTEND=noninteractive
    apt-get -y update
    # TODO: ENSURE THIS IS CONFIGURED CORRECTLY
    apt-get -y install unattended-upgrades fail2ban

    # create gluster, nfs or Azure Files mount point
    mkdir -p /azlamp
apt-get -y update

apt-get -y --force-yes install mysql-client 

phpVersion=`/usr/bin/php -r "echo PHP_VERSION;" | /usr/bin/cut -c 1,2,3`

# install pre-requisites
    apt-get install -y --fix-missing python-software-properties unzip

    # install the entire stack
    # passing php versions $phpVersion
    apt-get -y --force-yes install nginx php$phpVersion-fpm php$phpVersion php$phpVersion-cli php$phpVersion-curl php$phpVersion-zip

    # LAMP requirements
    apt-get -y update > /dev/null
    # passing php versions $phpVersion
    apt-get install -y --force-yes php$phpVersion-common php$phpVersion-soap php$phpVersion-json php$phpVersion-redis php$phpVersion-bcmath php$phpVersion-gd php$phpVersion-xmlrpc php$phpVersion-intl php$phpVersion-xml php$phpVersion-bz2 php-pear php$phpVersion-mbstring php$phpVersion-dev mcrypt >> /tmp/apt6.log
    PhpVer=$(get_php_version)
        apt-get install -y --force-yes php$phpVersion-mysql


# Set up initial LAMP dirs
    mkdir -p /azlamp/html
    mkdir -p /azlamp/certs
    mkdir -p /azlamp/data

# create_main_nginx_conf_on_controller 

function create_main_nginx_conf_on_controller
{
    local httpsTermination=${1} # "None" or anything else

    cat <<EOF > /etc/nginx/nginx.conf
user www-data;
worker_processes 2;
pid /run/nginx.pid;
events {
	worker_connections 2048;
}
http {
  sendfile on;
  server_tokens off;
  tcp_nopush on;
  tcp_nodelay on;
  keepalive_timeout 65;
  types_hash_max_size 2048;
  client_max_body_size 0;
  proxy_max_temp_file_size 0;
  server_names_hash_bucket_size  128;
  fastcgi_buffers 16 16k; 
  fastcgi_buffer_size 32k;
  proxy_buffering off;
  include /etc/nginx/mime.types;
  default_type application/octet-stream;
  access_log /var/log/nginx/access.log;
  error_log /var/log/nginx/error.log;
  set_real_ip_from   127.0.0.1;
  real_ip_header      X-Forwarded-For;
  #ssl_protocols TLSv1 TLSv1.1 TLSv1.2; # Dropping SSLv3, ref: POODLE
  #upgrading to TLSv1.2 and droping 1 & 1.1
  ssl_protocols TLSv1.2;
  #ssl_prefer_server_ciphers on;
  #adding ssl ciphers
  ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
  
  gzip on;
  gzip_disable "msie6";
  gzip_vary on;
  gzip_proxied any;
  gzip_comp_level 6;
  gzip_buffers 16 8k;
  gzip_http_version 1.1;
  gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy
  include /etc/nginx/conf.d/*.conf;
  include /etc/nginx/sites-enabled/*;
}
EOF
}
httpsTermination=VMSS
create_main_nginx_conf_on_controller $httpsTermination

function update_php_config_on_controller
{
    # php config
    PhpVer=$(get_php_version)
    PhpIni=/etc/php/${PhpVer}/fpm/php.ini
    sed -i "s/memory_limit.*/memory_limit = 512M/" $PhpIni
    sed -i "s/max_execution_time.*/max_execution_time = 18000/" $PhpIni
    sed -i "s/max_input_vars.*/max_input_vars = 100000/" $PhpIni
    sed -i "s/max_input_time.*/max_input_time = 600/" $PhpIni
    sed -i "s/upload_max_filesize.*/upload_max_filesize = 1024M/" $PhpIni
    sed -i "s/post_max_size.*/post_max_size = 1056M/" $PhpIni
    sed -i "s/;opcache.use_cwd.*/opcache.use_cwd = 1/" $PhpIni
    sed -i "s/;opcache.validate_timestamps.*/opcache.validate_timestamps = 1/" $PhpIni
    sed -i "s/;opcache.save_comments.*/opcache.save_comments = 1/" $PhpIni
    sed -i "s/;opcache.enable_file_override.*/opcache.enable_file_override = 0/" $PhpIni
    sed -i "s/;opcache.enable.*/opcache.enable = 1/" $PhpIni
    sed -i "s/;opcache.memory_consumption.*/opcache.memory_consumption = 256/" $PhpIni
    sed -i "s/;opcache.max_accelerated_files.*/opcache.max_accelerated_files = 8000/" $PhpIni

    # fpm config - overload this
    cat <<EOF > /etc/php/${PhpVer}/fpm/pool.d/www.conf
[www]
user = www-data
group = www-data
listen = /run/php/php${PhpVer}-fpm.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 3000
pm.start_servers = 20
pm.min_spare_servers = 22
pm.max_spare_servers = 30
EOF
}

update_php_config_on_controller

# restart Nginx
    systemctl restart nginx

function create_database {
    local dbIP=$1
    local dbadminloginazure=$2
    local dbadminpass=$3
    local applicationDbName=$4
    local wpDbUserId=$5
    local wpDbUserPass=$6

    # create database for application
    mysql -h $dbIP -u $dbadminloginazure -p$dbadminpass -e "CREATE DATABASE $applicationDbName CHARACTER SET utf8;"
    # grant user permission for database
    mysql -h $dbIP -u $dbadminloginazure -p$dbadminpass -e "GRANT ALL ON $applicationDbName.* TO $wpDbUserId IDENTIFIED BY '$wpDbUserPass';"
}

function download_wordpress_version {
    local wordpressPath=/azlamp/html
    #local path=/var/lib/waagent/custom-script/download/0
    local siteFQDN=$1
    local version=$2

    cd $wordpressPath
    wget https://wordpress.org/wordpress-$version.tar.gz
    tar -xvf $wordpressPath/wordpress-$version.tar.gz
    rm $wordpressPath/wordpress-$version.tar.gz
    mv $wordpressPath/wordpress $wordpressPath/$siteFQDN
}

function download_wordpress {
    local wordpressPath=/azlamp/html
    #local path=/var/lib/waagent/custom-script/download/0
    local siteFQDN=$1

    cd $wordpressPath
    wget https://wordpress.org/latest.tar.gz
    tar -xvf $wordpressPath/latest.tar.gz
    rm $wordpressPath/latest.tar.gz
    mv $wordpressPath/wordpress $wordpressPath/$siteFQDN
}

function create_wpconfig {
    local dbIP=$1
    local applicationDbName=$2
    local dbadminloginazure=$3
    local dbadminpass=$4
    local siteFQDN=$5

    cat <<EOF >/azlamp/html/$siteFQDN/wp-config.php
  <?php
  /**
  * Following configration file will be updated in the wordpress folder in runtime 
  *
  * Following configurations: Azure Database for MySQL server settings, Table Prefix,
  * Secret Keys, WordPress Language, and ABSPATH. 
  * 
  * wp-config.php  file is used during the installation.
  * Copy the wp-config file to wordpress folder.
  *
  */
  // ** Azure Database for MySQL server settings - You can get the following details from Azure Portal** //
  /** Database name for WordPress */
  define('DB_NAME', '$applicationDbName');
  /** username for MySQL database */
  define('DB_USER', '$dbadminloginazure');
  /** password for MySQL database */
  define('DB_PASSWORD', '$dbadminpass');
  /** Azure Database for MySQL server hostname */
  define('DB_HOST', '$dbIP');
  /** Database Charset to use in creating database tables. */
  define('DB_CHARSET', 'utf8');
  /** The Database Collate type. Don't change this if in doubt. */
  define('DB_COLLATE', '');
  /**
  * Authentication Unique Keys and Salts.
  * You can generate unique keys and salts at https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service
  * You can change these at any point in time to invalidate all existing cookies.
  */
  define('AUTH_KEY',         'h|Eu6ge.=Ej?fyV]/sHw:Ur~>(tkhZH(S^I[DHjE+OD}^MsG\`j0a/y8.n]@L8P{o');
  define('SECURE_AUTH_KEY',  '\`D2d-b,i1YmFQqOy/^]#p_G^fSXWyPm]e:)}H~BVIG\`>vG\$AnnYqUj^#*pPB;*,j');
  define('LOGGED_IN_KEY',    'Wqfh/&|XT| \$o0xeb+%Xf|_N;9Dpp19nzlB& b4w0I.D1;q<|-{4ajT\$JT(QF<@6');
  define('NONCE_KEY',        '89mwVzZXf2-[qjN+k-]#lbg8+>gxO%Fso9;-ptiUwqFS_4x-u\$6I<d,~v=mF2__|');
  define('AUTH_SALT',        't#ry@FfhD3,Y(lZf7+*V,&5rs(&\$xP,tz6[*<_&&CJW/]?2![NEQhsIi2vm-NYlZ');
  define('SECURE_AUTH_SALT', '9zIjp#dKMLLi{&Ag[Ig0Q]oP[[jN qNz<_Z= Gx#Ig/mi>k-J(oE6Prr&L[zR5Vp');
  define('LOGGED_IN_SALT',   '+(B*,@@5eH<?Mq7t-04>b>F%~C!6,+g?vf:w8N(Ne+nwA85N^U54#LHhssf1=>ap');
  define('NONCE_SALT',       'drEw_Z[MD z7Jv,t;WuR8&Q #z? D0c8RR!v*~mkSW1-PlXa9Bl>5&b|=Xe{z9a^');
  /**
  * WordPress Database Table prefix.
  *
  * You can have multiple installations in one database if you give each a unique prefix.
  * Only numbers, letters, and underscores are allowed.
  */
  \$table_prefix  = 'wp_';
  /**
  * WordPress Localized Language, defaults language is English.
  *
  * A corresponding MO file for the chosen language must be installed to wp-content/languages. 
  */
  define('WPLANG', '');
  /**
  * For developers: Debugging mode for WordPress.
  * Change WP_DEBUG to true to enable the display of notices during development.
  * It is strongly recommended that plugin and theme developers use WP_DEBUG in their development environments.
  */
  define('WP_DEBUG', false);
  /** Disable Automatic Updates Completely */
  define( 'AUTOMATIC_UPDATER_DISABLED', True );
  /** Define AUTOMATIC Updates for Components. */
  define( 'WP_AUTO_UPDATE_CORE', True );
  /** Absolute path to the WordPress directory. */
  if ( !defined('ABSPATH') )
    define('ABSPATH', dirname(__FILE__) . '/');
  /** Sets up WordPress vars and included files. */
  require_once(ABSPATH . 'wp-settings.php');
  /** Avoid FTP credentails. */
  define('FS_METHOD','direct');
EOF
}

function install_wp_cli {
    cd /tmp
    wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x /tmp/wp-cli.phar
    mv /tmp/wp-cli.phar /usr/local/bin/wp
}

function install_wordpress {
    local lbDns=$1
    local wpTitle=$2
    local wpAdminUser=$3
    local wpAdminPassword=$4
    local wpAdminEmail=$5
    local wpPath=$6

    wp core install --url=https://$lbDns --title=$wpTitle --admin_user=$wpAdminUser --admin_password=$wpAdminPassword --admin_email=$wpAdminEmail --path=$wpPath --allow-root
}

function install_plugins {
    local path=$1
    wp plugin install woocommerce --path=$path --allow-root
    wp plugin activate woocommerce --path=$path --allow-root
    wp plugin activate akismet --path=$path --allow-root
    chown -R www-data:www-data $path
}

function linking_data_location {
    local dataPath=/azlamp/data
    mkdir -p $dataPath/$1
    mkdir -p $dataPath/$1/wp-content
    mv /azlamp/html/$1/wp-content /tmp/wp-content
    ln -s $dataPath/$1/wp-content /azlamp/html/$1/
    mv /tmp/wp-content/* $dataPath/$1/wp-content/
    chmod 0755 $dataPath/$1/wp-content
    chown -R www-data:www-data $dataPath/$1
}

function generate_sslcerts {
    local path=/azlamp/certs/$1
    local thumbprintSslCert=$2
    local thumbprintCaCert=$3

    mkdir $path
    if [ "$thumbprintSslCert" != "None" ]; then
      echo "Using VM's cert (/var/lib/waagent/$thumbprintSslCert.*) for SSL..."
      cat /var/lib/waagent/$thumbprintSslCert.prv >$path/nginx.key
      cat /var/lib/waagent/$thumbprintSslCert.crt >$path/nginx.crt
      if [ "$thumbprintCaCert" != "None" ]; then
        echo "CA cert was specified (/var/lib/waagent/$thumbprintCaCert.crt), so append it to nginx.crt..."
        cat /var/lib/waagent/$thumbprintCaCert.crt >>$path/nginx.crt
      fi
    else
      echo -e "Generating SSL self-signed certificate"
      openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $path/nginx.key -out $path/nginx.crt -subj "/C=US/ST=WA/L=Redmond/O=IT/CN=$1"
    fi
    chmod 400 $path/nginx.*
    chown www-data:www-data $path/nginx.*
    chown -R www-data:www-data /azlamp/data/$1
}

function generate_text_file {
    local dnsSite=$1
    local username=$2
    local passw=$3
    local dbIP=$4
    local wpDbUserId=$5
    local wpDbUserPass=$6

    cat <<EOF >/home/wordpress.txt
WordPress Details
WordPress site name: $dnsSite
username: $username
password: $passw
Database details
db server name: $dbIP
wpDbUserId: $wpDbUserId
wpDbUserPass: $wpDbUserPass
EOF
}

function install_wordpress_application {
    local dnsSite=$siteFQDN
    local wpTitle=LAMP-WordPress
    local wpAdminUser=admin
    local wpAdminPassword=$wpAdminPass
    local wpAdminEmail=admin@$dnsSite
    local wpPath=/azlamp/html/$dnsSite
    local wpDbUserId=admin
    local wpDbUserPass=$wpDbUserPass

    # Creates a Database for CMS application
    create_database $dbIP $dbadminloginazure $dbadminpass $applicationDbName $wpDbUserId $wpDbUserPass
    # Download the wordpress application compressed file
    # download_wordpress $dnsSite
    download_wordpress_version $dnsSite $wpVersion
    # Links the data content folder to shared folder.. /azlamp/data
    linking_data_location $dnsSite
    # Creates a wp-config file for wordpress
    create_wpconfig $dbIP $applicationDbName $dbadminloginazure $dbadminpass $dnsSite
    # Installs WP-CLI tool
    install_wp_cli
    # Install WordPress by using wp-cli commands
    install_wordpress $dnsSite $wpTitle $wpAdminUser $wpAdminPassword $wpAdminEmail $wpPath
    # Install WooCommerce plug-in
    install_plugins $wpPath
    # Generates the openSSL certificates
    generate_sslcerts $dnsSite $thumbprintSslCert $thumbprintCaCert
    # Generate the text file
    generate_text_file $dnsSite $wpAdminUser $wpAdminPassword $dbIP $wpDbUserId $wpDbUserPass
}

install_wordpress_application