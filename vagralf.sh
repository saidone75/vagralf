#!/bin/bash

ALF_DOWNLOAD_URL=https://download.alfresco.com/cloudfront/release/community/7.0.0-build-2355/alfresco-content-services-community-distribution-7.0.0.zip
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
apt install mg tomcat9 postgresql zip unzip imagemagick --assume-yes &>> $LOGFILE

cd /vagrant
# download and unzip Alfresco community distribution
info "downloading Alfresco community distribution"
if [ ! -f $ALF_ZIP ]; then
    wget $ALF_DOWNLOAD_URL &>> $LOGFILE
fi
unzip $ALF_ZIP -d $ALF_DIR &>> $LOGFILE

info "configuring Tomcat and Alfresco"
# stop Tomcat
service tomcat9 stop &

# Tomcat config
sed '/<Resources/,/Resources>/d' $ALF_DIR/web-server/conf/Catalina/localhost/share.xml | sudo tee /etc/tomcat9/Catalina/localhost/share.xml &>> $LOGFILE
sed '/<Resources/,/Resources>/d' $ALF_DIR/web-server/conf/Catalina/localhost/alfresco.xml | sudo tee /etc/tomcat9/Catalina/localhost/alfresco.xml &>> $LOGFILE
sed -r 's#^(shared.loader=).*$#printf "%s%s" \1 "\\${catalina.base}/shared/classes,\\${catalina.base}/shared/lib/*.jar";#e' /etc/tomcat9/catalina.properties | sudo tee /etc/tomcat9/catalina.properties &>> $LOGFILE
sed '/^ReadWritePaths=\/var\/log\/tomcat9\//a ReadWritePaths=/srv/alfresco/' /etc/systemd/system/multi-user.target.wants/tomcat9.service | sudo tee /etc/systemd/system/multi-user.target.wants/tomcat9.service &>> $LOGFILE
systemctl daemon-reload

# PostgreSQL JDBC driver
cp $ALF_DIR/web-server/lib/* /usr/share/tomcat9/lib

# install Share Services AMP
java -jar $ALF_DIR/bin/alfresco-mmt.jar install $ALF_DIR/amps/* $ALF_DIR/web-server/webapps/alfresco.war

# Alfresco and Share WARs
rm -rf /var/lib/tomcat9/work/Catalina/*
rm -rf /var/lib/tomcat9/webapps/*

mkdir -p WEB-INF/classes
cp alfresco-log4j.properties WEB-INF/classes/log4j.properties
zip -qur $ALF_DIR/web-server/webapps/alfresco.war WEB-INF/classes/log4j.properties

cp share-log4j.properties WEB-INF/classes/log4j.properties
zip -qur $ALF_DIR/web-server/webapps/share.war WEB-INF/classes/log4j.properties
rm -rf WEB-INF

cp $ALF_DIR/web-server/webapps/{alfresco,share}.war /var/lib/tomcat9/webapps/

# Alfresco config
cp -r $ALF_DIR/web-server/shared /var/lib/tomcat9
cp alfresco-global.properties /var/lib/tomcat9/shared/classes/

# create alf_data and setting ownership
#cp -R alf_data /srv/alfresco
mkdir -p /srv/alfresco/alf_data/keystore/metadata-keystore
cp keystore /srv/alfresco/alf_data/keystore/metadata-keystore
chown -R tomcat:tomcat /srv/alfresco

# create Alfresco database and user
info "creating Alfresco database and user"
sudo -u postgres bash -c "psql -c \"CREATE DATABASE alfresco;\"" &>> $LOGFILE
sudo -u postgres bash -c "psql -c \"CREATE USER alfresco WITH PASSWORD 'alfresco';\"" &>> $LOGFILE
sudo -u postgres bash -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE alfresco TO alfresco;\"" &>> $LOGFILE

# increase Tomcat memory limit and set keystore properties
sed '/^#!\/bin\/sh/a JAVA_OPTS="-Xms2048m -Xmx2048m -Dencryption.keystore.type=JCEKS -Dencryption.cipherAlgorithm=DESede/CBC/PKCS5Padding -Dencryption.keyAlgorithm=DESede -Dencryption.keystore.location=/srv/alfresco/alf_data/keystore/metadata-keystore/keystore -Dmetadata-keystore.password=password -Dmetadata-keystore.aliases=metadata -Dmetadata-keystore.metadata.password=password -Dmetadata-keystore.metadata.algorithm=DESede"' /usr/share/tomcat9/bin/catalina.sh | sudo tee /usr/share/tomcat9/bin/catalina.sh &>> $LOGFILE

# ...and restart Tomcat!
info "starting Tomcat"
cat /dev/null > /var/log/tomcat9/alfresco.log
chown tomcat:adm /var/log/tomcat9/alfresco.log
service tomcat9 start &

# install alfresco-pdf-renderer
#tar -xzf $ALF_DIR/alfresco-pdf-renderer/alfresco-pdf-renderer-1.1-linux.tgz -C /usr/bin/

# wait for Alfresco deployment
info "waiting for Alfresco deployment"
while ! sudo grep "Alfresco Content Services started" /var/log/tomcat9/alfresco.log; do sleep 5; done
info "done!"

# remove unzipped directory, leave zip archive
rm -rf $ALF_DIR
