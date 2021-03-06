#!/bin/bash
#Script to install OCS Inventory Server on Ubuntu Server 12.04

#
# check for permissions - must run as root
#
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root/sudo user"
	exit 1
fi 

### install package
apt-get -y update
apt-get -y install ocsinventory-server 

### set reasonable limits
sed -i "s/post_max_size.*/post_max_size = 201M/" /etc/php5/apache2/php.ini
sed -i "s/upload_max_filesize.*/upload_max_filesize = 200M/" /etc/php5/apache2/php.ini

### install Perl Modules
apt-get -y install make libapache2-mod-perl2-dev
cpan Apache2::SOAP
cpan XML::Entities

### run the web installer
service apache2 restart
echo
echo "Please visit http://<hostname>/ocsreports now to complete the setup."
echo "Use the root mysql user and password when prompted."
read -p "Once the config is complete, press Enter to continue."
echo

### change DB password
mv /usr/share/ocsinventory-reports/install.php /usr/share/ocsinventory-reports/install.php.orig
echo "Enter new password for mysql database 'ocsweb'."
read MYSQLPASSWD
echo "Enter root password for mysql."
mysql -h localhost -u root -p mysql -e "SET PASSWORD FOR 'ocs'@'localhost' = PASSWORD('$MYSQLPASSWD');"
sed -i "s/PSWD_BASE\",\"ocs/PSWD_BASE\",\"$MYSQLPASSWD/" /usr/share/ocsinventory-reports/dbconfig.inc.php
sed -i "s/OCS_DB_PWD ocs/OCS_DB_PWD $MYSQLPASSWD/" /etc/ocsinventory/ocsinventory.conf

### generate SSL cert for use w/ package deployment
a2ensite default-ssl
a2enmod ssl
make-ssl-cert generate-default-snakeoil --force-overwrite
service apache2 restart
cp /etc/ssl/certs/ssl-cert-snakeoil.pem ./cacert.pem

### admin password must be changed through the web
echo "Please change the Super Admin password via web interface."
echo "cacert.pem has been created in the current directory"
echo "- it is required for automatic package deployment."
