#!/bin/bash

. 00_prereq.sh
#sed $(for f in CONTROLLER COMPUTE NETWORK STORAGE SAHARA AMQP MYSQL REDIS; do echo -n "-e "; echo -n "'s/%${f}LIST%/\$IPADDR/g' "; done) < files/dmzcloud.ans.template
#cp files/dmzcloud.ans /root/${HOST}.ans
#export IPADDR=$(cat /etc/hosts | grep dmzcloud | awk '{print $1}')
#export HOST=$(cat /etc/hosts | grep dmzcloud | awk '{print $2}')

packstack_setup
packstack_build

