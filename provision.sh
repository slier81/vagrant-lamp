#!/bin/bash

# Credential Variable
MYSQL_PASS='root'
PHPMYADMIN_PASS='root'

# Config File
php_config_file='/etc/php5/apache2/php.ini'
xdebug_config_file='/etc/php5/mods-available/xdebug.ini'
mysql_config_file='/etc/mysql/my.cnf'
mailcatcher_config_file='/etc/init/mailcatcher.conf'

IPADDR=$(/sbin/ifconfig eth0 | awk '/inet / { print $2 }' | sed 's/addr://')
sed -i "s/^${IPADDR}.*//" hosts
echo $IPADDR ubuntu.localhost >> /etc/hosts			# Just to quiet down some error messages

# Update the server
apt-get update
apt-get -y upgrade

# Install basic tools
apt-get -y install build-essential binutils-doc git

# Install Apache
apt-get -y install apache2
apt-get -y install php5 php5-curl php5-mysql php5-sqlite php5-xdebug

# Configure Php
sed -i "s/display_startup_errors = Off/display_startup_errors = On/g" $php_config_file
sed -i "s/display_errors = Off/display_errors = On/g" $php_config_file

# Configure Xdebug
echo "xdebug.remote_enable=1" >> $xdebug_config_file
echo "xdebug.remote_connect_back=1" >> $xdebug_config_file
echo "xdebug.profiler_enable_trigger=1" >> $xdebug_config_file
echo "xdebug.profiler_output_dir=\"/vagrant/cachegrind\"" >> $xdebug_config_file
echo "xdebug.profiler_output_name=\"cachegrind.out.%H.%t\"" >> $xdebug_config_file

# Configure MySql
echo "mysql-server mysql-server/root_password password $MYSQL_PASS" | debconf-set-selections
echo "mysql-server mysql-server/root_password_again password $MYSQL_PASS" | debconf-set-selections

# Configure PhpMyadmin
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password $PHPMYADMIN_PASS" | debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password $PHPMYADMIN_PASS" | debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/admin-pass password $PHPMYADMIN_PASS" | debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections

# Install MySQL & PhpMyadmin
apt-get -y install mysql-client mysql-server phpmyadmin

# Fix mcrypt extension error in phpmyadmin
php5enmod mcrypt

#Enable apache mod rewrite
a2enmod rewrite
sed -ie '\#<Directory /var/www/>#, \#</Directory># s/AllowOverride None/AllowOverride All/i' /etc/apache2/apache2.conf

# Make Mysql daemon accessible through any host
sed -i "s/bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/" $mysql_config_file

# Allow root access from any host
echo "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY 'root' WITH GRANT OPTION" | mysql -u root --password=$MYSQL_PASS
echo "GRANT PROXY ON ''@'' TO 'root'@'%' WITH GRANT OPTION" | mysql -u root --password=$MYSQL_PASS

# Install Composer
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

# Install Mailcatcher Dependencies (sqlite, ruby)
apt-get install -y libsqlite3-dev ruby1.9.1-dev

# Install Mailcatcher as a Ruby gem
gem install mailcatcher

# Create Mailcatcher upstart
cat > $mailcatcher_config_file << EOL
description 'Mailcatcher'

start on runlevel [2345]
stop on runlevel [!2345]

respawn

exec /usr/bin/env $(which mailcatcher) --foreground --http-ip=0.0.0.0
EOL

# Enable Mailcatcher with php
echo "sendmail_path = /usr/bin/env $(which catchmail) -f webmaster@localhost" | tee /etc/php5/mods-available/mailcatcher.ini
php5enmod mailcatcher

# Start service
service apache2 restart
service mysql restart
service mailcatcher start