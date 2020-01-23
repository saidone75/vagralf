#!/bin/bash

ALF_DOWNLOAD_URL=https://download.alfresco.com/cloudfront/release/community/201911-GA-build-368/alfresco-content-services-community-distribution-6.2.0-ga.zip
LOGFILE=/vagrant/vagralf.log

IFS=$'\n'

DEBUG=1
COLOUR=1

ALF_ZIP=$(sed s/^.*[\/]// <<< $ALF_DOWNLOAD_URL)
ALF_DIR=$(sed s/\.[^\.]*$// <<< $ALF_ZIP)

function info() {
	  for LINE in $1; do
		    if [ $COLOUR -eq 0 ]; then
			      echo "[I] $LINE"|tee -a $LOGFILE
		    else
			      echo -e "\033[0;32m[I]\033[0;370m $LINE" && echo "[I] $LINE" >> $LOGFILE
		    fi
	  done
}

function debug() {
	  for LINE in $1; do
		    if [ $DEBUG -eq 1 ]; then
			      if [ $COLOUR -eq 0 ]; then
				        echo "[D] $LINE"|tee -a $LOGFILE
			      else
				        echo -e "\033[0;33m[D]\033[0;370m $LINE" && echo "[D] $LINE" >> $LOGFILE
			      fi
		    fi
	  done
}

function fatal() {
	  for LINE in $1; do
		    if [ $COLOUR -eq 0 ]; then
			      echo "[F] $LINE"|tee -a $LOFGILE
		    else
			      echo -e "\033[0;31m[F]\033[0;370m $LINE" && echo "[F] $LINE" >> $LOGFILE
		    fi
		    exit 1
	  done
}

# update list of available packages
info "updating list of available packages"
apt update &> $LOGFILE

# install required packages
info "installing required packages"
apt install openjdk-11-jre-headless tomcat8 postgresql unzip imagemagick --assume-yes &>> $LOGFILE

cd /vagrant
# download and unzip Alfresco community distribution
info "downloading Alfresco community distribution"
if [ ! -f $ALF_ZIP ]; then
    wget $ALF_DOWNLOAD_URL &>> $LOGFILE
fi
unzip $ALF_ZIP &>> $LOGFILE

info "configuring Tomcat and Alfresco"
# stop Tomcat
service tomcat8 stop &

# Tomcat config
sed '/<Resources/,/Resources>/d' $ALF_DIR/web-server/conf/Catalina/localhost/share.xml | sudo tee /etc/tomcat8/Catalina/localhost/share.xml &>> $LOGFILE
sed '/<Resources/,/Resources>/d' $ALF_DIR/web-server/conf/Catalina/localhost/alfresco.xml | sudo tee /etc/tomcat8/Catalina/localhost/alfresco.xml &>> $LOGFILE

# PostgreSQL JDBC driver
cp $ALF_DIR/web-server/lib/* /usr/share/tomcat8/lib

# install Share Services AMP
java -jar $ALF_DIR/bin/alfresco-mmt.jar install $ALF_DIR/amps/* $ALF_DIR/web-server/webapps/alfresco.war

# Alfresco and Share WARs
rm -rf /var/lib/tomcat8/work/Catalina/*
rm -rf /var/lib/tomcat8/webapps/*
cp $ALF_DIR/web-server/webapps/{alfresco,share}.war /var/lib/tomcat8/webapps/

# Alfresco config       
cp -r $ALF_DIR/web-server/shared /usr/share/tomcat8/shared
cp alfresco-global.properties /usr/share/tomcat8/shared/classes/

# create alf_data and setting ownership
mkdir -p /srv/alfresco
cp -R $ALF_DIR/alf_data /srv/alfresco
chown -R tomcat8:tomcat8 /srv/alfresco

# create Alfresco database and user
info "creating Alfresco database and user"
sudo -u postgres bash -c "psql -c \"CREATE DATABASE alfresco;\"" &>> $LOGFILE
sudo -u postgres bash -c "psql -c \"CREATE USER alfresco WITH PASSWORD 'alfresco';\"" &>> $LOGFILE
sudo -u postgres bash -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE alfresco TO alfresco;\"" &>> $LOGFILE

# increase Tomcat memory limit...
sed '/^#!\/bin\/sh/a JAVA_OPTS="-Xms2048m -Xmx2048m"' /usr/share/tomcat8/bin/catalina.sh | sudo tee /usr/share/tomcat8/bin/catalina.sh &>> $LOGFILE

# ...and restart Tomcat!
info "starting Tomcat"
cat /dev/null > /var/log/tomcat8/catalina.out
service tomcat8 start &

# install alfresco-pdf-renderer
tar -xzf $ALF_DIR/alfresco-pdf-renderer/alfresco-pdf-renderer-1.1-linux.tgz -C /usr/bin/

# wait for Alfresco deployment
info "waiting for Alfresco deployment"
while ! sudo grep "Alfresco Content Services started" /var/log/tomcat8/catalina.out; do sleep 5; done
info "done!"

# remove unzipped directory, leave zip archive
rm -rf $ALF_DIR
