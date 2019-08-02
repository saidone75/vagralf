#!/bin/bash

IFS=$'\n'

DEBUG=1
COLOUR=1

LOGFILE=/vagrant/vagralf.log

function info() {
	for LINE in $1; do
		if [ $COLOUR -eq 0 ]; then
			echo -e "[INFO] $LINE"
		else
			echo -e "\t\033[0;32m[INFO]\033[0;370m $LINE"
		fi
	done
}

function debug() {
	for LINE in $1; do
		if [ $DEBUG -eq 1 ]; then
			if [ $COLOUR -eq 0 ]; then
				echo -e "[DEBUG] $LINE"
			else
				echo -ne "\t\033[0;33m[DEBUG]\033[0;370m $LINE"
			fi
		fi
	done
}

function fatal() {
	for LINE in $1; do
		if [ $COLOUR -eq 0 ]; then
			echo -e "[FATAL] $LINE"
		else
			echo -e "\t\033[0;31m[FATAL]\033[0;370m $LINE"
		fi
		exit 1
	done
}

# update list of available packages
info "updating list of available packages"
apt update &> $LOGFILE

# install required packages
info "installing required packages"
apt install openjdk-8-jre-headless tomcat7 postgresql unzip imagemagick --assume-yes &>> $LOGFILE

cd /vagrant
# download and unzip Alfresco community distribution
info "downloading Alfresco community distribution"
if [ ! -f alfresco-content-services-community-distribution-6.1.2-ga.zip ]; then
    wget https://download.alfresco.com/cloudfront/release/community/201901-GA-build-205/alfresco-content-services-community-distribution-6.1.2-ga.zip &>> $LOGFILE
fi
unzip alfresco-content-services-community-distribution-6.1.2-ga.zip &>> $LOGFILE
export ALFRESCO=alfresco-content-services-community-distribution-6.1.2-ga

info "configuring Tomcat and Alfresco"
# stop Tomcat
service tomcat7 stop

# Tomcat config
cp $ALFRESCO/web-server/conf/Catalina/localhost/* /etc/tomcat7/Catalina/localhost

# PostgreSQL JDBC driver
cp $ALFRESCO/web-server/lib/* /usr/share/tomcat7/lib

# Alfresco and Share WARs
rm -rf /var/lib/tomcat7/work/Catalina/localhost/* 
rm -rf /var/lib/tomcat7/webapps/*
cp $ALFRESCO/web-server/webapps/{alfresco,share}.war /var/lib/tomcat7/webapps/

# Alfresco config       
cp -r $ALFRESCO/web-server/shared /usr/share/tomcat7/shared
cp alfresco-global.properties /usr/share/tomcat7/shared/classes/

# create alf_data and setting ownership
mkdir -p /srv/alfresco
cp -R $ALFRESCO/alf_data /srv/alfresco
chown -R tomcat7:tomcat7 /srv/alfresco

# create Alfresco database and user
info "creating Alfresco database and user"
sudo -u postgres bash -c "psql -c \"CREATE DATABASE alfresco;\"" &>> $LOGFILE
sudo -u postgres bash -c "psql -c \"CREATE USER alfresco WITH PASSWORD 'alfresco';\"" &>> $LOGFILE
sudo -u postgres bash -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE alfresco TO alfresco;\"" &>> $LOGFILE

# increase Tomcat memory limit...
sed '/^#!\/bin\/sh/a JAVA_OPTS="-Xmx2048m"' /usr/share/tomcat7/bin/catalina.sh | tee /usr/share/tomcat7/bin/catalina.sh &>> $LOGFILE

# ...and restart Tomcat!
info "starting Tomcat"
service tomcat7 start

# wait for Alfresco deployment
info "waiting for Alfresco deployment"
while ! sudo grep "INFO: Deployment of configuration descriptor /etc/tomcat7/Catalina/localhost/alfresco.xml has finished" /var/log/tomcat7/catalina.out; do sleep 10; done
info "done!"

# remove unzipped directory, leave zip archive
rm -rf alfresco-content-services-community-distribution-6.1.2-ga
