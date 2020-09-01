#!/bin/bash

export LOGPATH=/var/log/nodelogic.log

function get_ipaddr() {
	cat /etc/hosts | grep dmzcloud | awk '{print $1}'
}
function get_host() {
	cat /etc/hosts | grep dmzcloud | awk '{print $2}'
}

function update_system() {
	yum update -y | tee -a $LOGPATH

	#its always dns
	cat /etc/resolv.conf | grep -qe "^nameserver"
	if [ $? -ne 0 ]; then
		echo "Adding nameserver" | tee -a $LOGPATH
		echo "nameserver 8.8.8.8" >> /etc/resolv.conf
	fi

	#add localhost as hosts entry
	cat /etc/hosts | grep -q "$(hostname)\$"
	if [ $? -ne 0 ]; then
		echo "/ETC/HOSTS: $(ip a show dev eth0 | grep 'inet ' | awk '{print $2}' | grep -v '::' | cut -d'/' -f1) $(hostname)" | tee -a $LOGPATH
		echo "$(ip a show dev eth0 | grep 'inet ' | awk '{print $2}' | grep -v '::' | cut -d'/' -f1) $(hostname)" >> /etc/hosts
	fi

	#allow root with pubkey
	sed -e 's/^PermitRootLogin/#PermitRootLogin/' -i /etc/ssh/sshd_config
	echo "PermitRootLogin without-password" >> /etc/ssh/sshd_config
	echo "Port 22" >> /etc/ssh/sshd_config
	echo "Port 220" >> /etc/ssh/sshd_config
	service sshd restart | tee -a $LOGPATH

	#local host is known host
	cat ~/.ssh/known_hosts | grep -q "$(hostname)\$"
	if [ $? -ne 0 ]; then
		mkdir -p ~/.ssh
		echo "$(hostname) $(cat /etc/ssh/ssh_host_ecdsa_key.pub)" >> ~/.ssh/known_hosts
		echo "$(cat /etc/hosts | grep $(hostname) | awk '{print $1}') $(cat /etc/ssh/ssh_host_ecdsa_key.pub)" >> ~/.ssh/known_hosts
		chmod 600 ~/.ssh/known_hosts
		chmod 700 ~/.ssh
	fi

}

function install_openstack() {
	yum install -y epel-release centos-release-openstack-train yum-plugin-versionlock | tee -a $LOGPATH
	yum install -y openvpn openstack-packstack | tee -a $LOGPATH
	rpm -qva |grep -q leatherman-1.3
	if [ $? -ne 0 ]; then
		yum downgrade -y leatherman
	fi
	yum versionlock add leatherman | tee -a $LOGPATH
}

function uninstall_openstack() {
	EVIL_VILLANS="openstack|neutron|rabbitmq-server|httpd|ovn|memcached|redis"
	SKIPPED_DB='mysql|information_schema|performance_schema|test|\+|Database'
	DELETE_USERS_SQL="delete from user where user != 'root';"
	DELETE_DB_SQL="delete from db where db not like 'test%';"
	FLUSH_SQL="flush privileges;"
	SHOW_DB_SQL="show databases;"
	systemctl list-unit-files | egrep -e "($EVIL_VILLANS)" | grep enabled |cut -d '.' -f 1 | tee -a $LOGPATH
	for f in $( systemctl list-unit-files | egrep -e "($EVIL_VILLANS)" | grep enabled |cut -d '.' -f 1);  do
		service $f stop | tee -a $LOGPATH
		#systemctl disable $f
	done


	mysql -e "$SHOW_DB_SQL" | egrep -ve "($SKIPPED_DB)" | tee -a $LOGPATH
	for f in $(mysql -e "$SHOW_DB_SQL" | egrep -ve "($SKIPPED_DB)"); do
		mysqladmin -u root -f drop $f | tee -a $LOGPATH
	done

	mysql -u root mysql -e "$DELETE_USERS_SQL" | tee -a $LOGPATH
	mysql -u root mysql -e "$DELETE_DB_SQL" | tee -a $LOGPATH
	mysql -u root mysql -e "$FLUSH_SQL" | tee -a $LOGPATH
}

function packstack_setup() {
	HOST=$(get_host)
	IPADDR=$(get_ipaddr)
	if [ ! -f /root/${HOST}.ans ]; then
		packstack --gen-answer-file=/root/${HOST}.ans
	fi
	#cat /root/${HOST}.ans | egrep -ve '^(#|$)' > /root/${HOST}.anw
	#mv -f /root/${HOST}.anw /root/${HOST}.ans

	sed -e "s/%CONTROLLERLIST%/$IPADDR/g" -e "s/%COMPUTELIST%/$IPADDR/g" -e "s/%NETWORKLIST%/$IPADDR/g" -e "s/%STORAGELIST%/$IPADDR/g" -e "s/%SAHARALIST%/$IPADDR/g" -e "s/%AMQPLIST%/$IPADDR/g" -e "s/%MYSQLLIST%/$IPADDR/g" -e "s/%REDISLIST%/$IPADDR/g" -e "s/%LDAPSERVER%/$IPADDR/g" -e "s/%HOSTNAME%/$HOST/g" < files/dmzcloud.ans.template >> /root/${HOST}.anw
	IFS=$'\n'
	for line in $(cat /root/${HOST}.anw | egrep -ve '^(#|$)'); do
		SNIP=$(echo $line | cut -d'=' -f1)
		ANS=$(echo $line | cut -d'=' -f2- | sed -e 's/\//\\\//g')
		echo "$SNIP -> $ANS"
		sed -e "s/^${SNIP}=.*$/${SNIP}=${ANS}/" -i /root/${HOST}.ans 
	done
	cp /root/${HOST}.ans /root/${HOST}-original.ans
}

function packstack_build() {
	HOST=$(get_host)
	if [ ! -f /root/.ssh/id_rsa ]; then
		mkdir /root/.ssh
		ssh-keygen -f /root/.ssh/id_rsa | tee -a $LOGFILE
		cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
		chmod 700 /root/.ssh
		chmod 600 /root/.ssh/authorized_keys /root/.ssh/id_rsa
	fi

	time packstack --answer-file=/root/${HOST}.ans 2>&1 | tee -a $LOGFILE
	echo $? | tee -a $LOGFILE
	sleep 5
	cat /etc/resolv.conf | grep -qe "^nameserver"
	if [ $? -ne 0 ]; then
		echo "Adding nameserver" | tee -a $LOGPATH
		echo "nameserver 8.8.8.8" >> /etc/resolv.conf
		time packstack --answer-file=/root/${HOST}.ans 2>&1 | tee -a $LOGFILE
	fi
	cat /proc/cpuinfo |egrep -e '(processor|model name)' | tail -2 | tee -a $LOGFILE
}
