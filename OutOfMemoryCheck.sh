#!/bin/bash
#set -x

export BIN={INSTALL_HOME}
export TIBCO_HOME={INSTALL_HOME}}
export BW_HOME=${TIBCO_HOME}/bw/6.4
export BW_BIN=${BW_HOME}/bin
export LOGDIR={LOGDIR}


if [ -f ${BIN}/setenv.sh ]
then
        . ${BIN}/setenv.sh
else
        echo setenv.sh NOT Found...
        exit 1
fi

#File_log is for Email Report and File_debug is detailed log of script operation

File_log={INSTALL_HOME}/tmp/heapdump_$(whoami).txt
File_debug={INSTALL_HOME}/tmp/heapdump_debug_$(whoami).txt
ENABLE_EMAIL=0
#echo "Checking Appnodes for HeapDump Files"

[ -d ${LOGDIR}/dump ] || mkdir ${LOGDIR}/dump


#cleanup operation
#delete debug file if bigger than 1GB
`find {INSTALL_HOME}/tmp/ -size +1024M -name heapdump_debug_$(whoami).txt -exec rm -rf {} \;`
#delete 45 days older dump file from LOGDIR/dump folder
`find ${LOGDIR}/dump -mindepth 1 -mtime +45 -delete`


[ -e {INSTALL_HOME}/tmp/heapdump_$(whoami).txt ] && rm {INSTALL_HOME}/tmp/heapdump_$(whoami).txt

cat {INSTALL_HOME}/HeapMemCheck/web-part1.html >> ${File_log}


echo "#################################################################PROGRAME BEGIN#################################################################" >>${File_debug}
echo "`date +"%m-%d-%Y-%T"` - Programe Starting now to check for each dump file" >>${File_debug}


echo "`date +"%m-%d-%Y-%T"` - OutOfMemory check start for all Appnodes" >>${File_debug}
Command=`ls -ltr $TIBCO_HOME/bw/6.4/domains/*/appnodes/*/*/bin/java_*.hprof 2>/dev/null`
export RC=$?

if [ $RC -eq 0 ]
then
	PID=`ls -ltr $TIBCO_HOME/bw/6.4/domains/*/appnodes/*/*/bin/java_*.hprof|sed 's/.*\///g'|sed 's/^java_pid//g'|sed 's/\.hprof$//g'`


	echo "`date +"%m-%d-%Y-%T"` - Detaected Files" >>${File_debug}
	echo "`date +"%m-%d-%Y-%T"` - $Command" >>${File_debug}

	
	for i in `echo $PID`;
	do 
		unset MOVE_TO_LOGDUMP
		unset APPNODE_STATUS_POST_RESTART
		echo "`date +"%m-%d-%Y-%T"` - Iteration begin for PID $i" >>${File_debug}
		PROCESS=`pwdx $i 2>/dev/null`
		RC_Process_Check=$?
		if [ $RC_Process_Check -eq 1 ]
		then 
			echo "`date +"%m-%d-%Y-%T"` - Process with pid $i not found" >>${File_debug}
			echo "`date +"%m-%d-%Y-%T"` - Moving file to ${LOGDIR}/dump" >>${File_debug}
			`mv $TIBCO_HOME/bw/6.4/domains/*/*/*/*/bin/java_pid${i}.hprof $LOGDIR/dump/`
			echo "`date +"%m-%d-%Y-%T"` - Iteration terminating for pid $i" >>${File_debug}
			continue
		fi
		#Dump file set, enabling email
		ENABLE_EMAIL=1
		DOMAIN=`echo "$PROCESS"|awk -F"/" '{print $8}'`
		APPSPACE=`echo "$PROCESS"|awk -F"/" '{print $10}'`
		APPNODE=`echo "$PROCESS"|awk -F"/" '{print $11}'`
		
		echo "`date +"%m-%d-%Y-%T"` - Heap Dump file found on domain $DOMAIN Appspace $APPSPACE Appnode $APPNODE on Server `hostname` with TIBCO_HOME $TIBCO_HOME" >>${File_debug}

		#Rotating Heap Dump log, Moving heap dump file to LOGDIR

		echo "`date +"%m-%d-%Y-%T"` - Moving file $TIBCO_HOME/bw/6.4/domains/${DOMAIN}/appnodes/${APPSPACE}/${APPNODE}/bin/java_pid${i}.hprof => $LOGDIR/dump/${DOMAIN}_${APPNODE}_${APPSPACE}_java_pid${i}.hprof" >> ${File_debug}

		`mv $TIBCO_HOME/bw/6.4/domains/${DOMAIN}/appnodes/${APPSPACE}/${APPNODE}/bin/java_pid${i}.hprof $LOGDIR/dump/${DOMAIN}_${APPNODE}_${APPSPACE}_java_pid${i}.hprof`
		RC_Move=$?
		if [ $RC_Move -eq 0 ]
		then
			MOVE_TO_LOGDUMP=SUCCESSFULL
		else
			echo "`date +"%m-%d-%Y-%T"` - Move has failed" >> ${File_debug}
		fi

		#Checking Status of Appnode, If Unrechable then Configstore clear and restart appnode
		
		cd $TIBCO_HOME/bw/6.4/bin/
		$TIBCO_HOME/bw/6.4/bin/bwadmin show -domain $DOMAIN -appspace $APPSPACE -appnode $APPNODE > {INSTALL_HOME}/tmp/${APPNODE}_$(whoami).txt
		echo "`date +"%m-%d-%Y-%T"` - AppNode $APPNODE Status Check ->" >> ${File_debug}
		cat {INSTALL_HOME}/tmp/${APPNODE}_$(whoami).txt >> ${File_debug}
		APPNODE_STATUS=`cat {INSTALL_HOME}/tmp/${APPNODE}_$(whoami).txt|tail -1|awk -F' ' '{print $2}'`
		
		#Something to work in future
		#$TIBCO_HOME/bw/6.4/bin/bwadmin show -domain $DOMAIN -appspace $APPSPACE -appnode $APPNODE bwengine >> {INSTALL_HOME}/tmp/heapdump_$(whoami).txt;
		
		if [ $APPNODE_STATUS = "Unreachable" ]
			then
				echo "`date +"%m-%d-%Y-%T"` - Appnode is in Unreachable state, proceeding with clearing configstore and restart of AppNode" >> ${File_debug}
				echo "`date +"%m-%d-%Y-%T"` - Status of applications before restart of Appnode" >> ${File_debug}
				cd $TIBCO_HOME/bw/6.4/bin/
				$TIBCO_HOME/bw/6.4/bin/bwadmin show -domain $DOMAIN -appspace $APPSPACE -appnode $APPNODE applications >> ${File_debug}
				echo "`date +"%m-%d-%Y-%T"` - kill -9 $i" >> ${File_debug}
				kill -9 $i
				sleep 5
				echo "`date +"%m-%d-%Y-%T"` - Clearing Config Store" >> ${File_debug}
				echo "`date +"%m-%d-%Y-%T"` - rm -rf $TIBCO_HOME/bw/6.4/domains/$DOMAIN/appnodes/$APPSPACE/$APPNODE/config/*" >> ${File_debug}
				rm -rf $TIBCO_HOME/bw/6.4/domains/$DOMAIN/appnodes/$APPSPACE/$APPNODE/config/*
				echo "`date +"%m-%d-%Y-%T"` - Starting Appnode $APPNODE of appspace $APPSPACE of domain $DOMAIN" >> ${File_debug}
				cd $TIBCO_HOME/bw/6.4/bin/
				$TIBCO_HOME/bw/6.4/bin/bwadmin start -domain $DOMAIN -appspace $APPSPACE -appnode $APPNODE >> ${File_debug}
				sleep 20
				echo "`date +"%m-%d-%Y-%T"` - Status Check after restart" >> ${File_debug}
				$TIBCO_HOME/bw/6.4/bin/bwadmin show -domain $DOMAIN -appspace $APPSPACE -appnode $APPNODE >> {INSTALL_HOME}/tmp/${APPNODE}_$(whoami).txt
				cat {INSTALL_HOME}/tmp/${APPNODE}_$(whoami).txt >> ${File_debug}
				APPNODE_STATUS_POST_RESTART=`cat {INSTALL_HOME}/tmp/${APPNODE}_$(whoami).txt|tail -1|awk -F' ' '{print $2}'`
				echo "`date +"%m-%d-%Y-%T"` - Status of $APPNODE post restart is $APPNODE_STATUS_POST_RESTART" >> ${File_debug}
				
		fi
		echo "<tr><td>`hostname`</td><td>$TIBCO_HOME</td><td>$DOMAIN</td><td>$APPSPACE</td><td>$APPNODE</td><td>$i</td><td>$MOVE_TO_LOGDUMP</td><td>$APPNODE_STATUS</td><td>$APPNODE_STATUS_POST_RESTART</td></tr>" >> ${File_log}
	echo "`date +"%m-%d-%Y-%T"` - Iteration finished successfully for pid $i" >> ${File_debug}
	done
	#cat {INSTALL_HOME}/HeapMemCheck/web-part2.html >>${File_log}
	#exit 0
else 
	echo "`date +"%m-%d-%Y-%T"` - No dump file found for Appnodes" >>${File_debug}
	#exit 1
fi

######Out of Memory check start for bwagent here

echo "`date +"%m-%d-%Y-%T"` - OutOfMemory check start for all bwagent" >>${File_debug}

Command1=`ls -ltr $TIBCO_HOME/bw/6.4/bin/java_*.hprof 2>/dev/null`
export RC1=$?

if [ $RC1 -eq 0 ]
then
	
	PID1=`ls -ltr $TIBCO_HOME/bw/6.4/bin/java_*.hprof|sed 's/.*\///g'|sed 's/^java_pid//g'|sed 's/\.hprof$//g'`

	echo "`date +"%m-%d-%Y-%T"` - Detaected Files" >>${File_debug}
        echo "`date +"%m-%d-%Y-%T"` - $Command1" >>${File_debug}
	
	for x in `echo $PID1`;
        do
		unset MOVE_TO_LOGDUMP1
		unset BWAGENT_STATUS_POST_RESTART
		echo "`date +"%m-%d-%Y-%T"` - Iteration begin for PID $x of bwagent" >>${File_debug}
		PROCESS1=`pwdx $x 2>/dev/null`
		RC1_Process_Check=$?
		if [ $RC1_Process_Check -eq 1 ]
                then
                        echo "`date +"%m-%d-%Y-%T"` - Process with pid $x not found" >>${File_debug}
                        echo "`date +"%m-%d-%Y-%T"` - Moving file to ${LOGDIR}/dump" >>${File_debug}
                        `mv $TIBCO_HOME/bw/6.4/bin/java_pid${x}.hprof $LOGDIR/dump/heapdumpfor_java_pid${x}.hprof`
                        echo "`date +"%m-%d-%Y-%T"` - Iteration terminating for pid $x" >>${File_debug}
                        continue
                fi
		echo "`date +"%m-%d-%Y-%T"` - Moving file to ${LOGDIR}/dump" >>${File_debug}
                `mv $TIBCO_HOME/bw/6.4/bin/java_pid${x}.hprof $LOGDIR/dump/heapdumpfor_java_pid${x}.hprof`
		cd ${BW_BIN}
                ${BW_BIN}/bwadmin show agents|grep `hostname` >{INSTALL_HOME}/tmp/bwagent_status_pre_$(whoami).txt
		echo "`date +"%m-%d-%Y-%T"` - checking Status of BWAGENT - " >>${File_debug}
		cat {INSTALL_HOME}/tmp/bwagent_status_pre_$(whoami).txt >>${File_debug}		
		BWAGENT_STATUS_PRE_RESTART=`cat {INSTALL_HOME}/tmp/bwagent_status_pre_$(whoami).txt |tail -1 |awk -F" " '{print $2}'`
		if [ $BWAGENT_STATUS_PRE_RESTART = "Running" ]
        		then
                	echo "Status of BWAGENT IS $BWAGENT_STATUS_PRE_RESTART, check finished for pind $x" >>${File_debug}
		elif [ $BWAGENT_STATUS_PRE_RESTART = "Unreachable" ]
		        then
			cat {INSTALL_HOME}/HeapMemCheck/web-part2.html >> ${File_log}
			echo "`date +"%m-%d-%Y-%T"` -Stopping BWAGENT" >>${File_debug}
			cd ${BW_BIN}
			`{INSTALL_HOME}/initBWAGENT.sh stop`
			echo "`date +"%m-%d-%Y-%T"` -Starting BWAGENT" >>${File_debug}
			`{INSTALL_HOME}/initBWAGENT.sh start`
			cd ${BW_BIN}
	                ${BW_BIN}/bwadmin show agents|grep `hostname` >{INSTALL_HOME}/tmp/bwagent_status_post_$(whoami).txt
			BWAGENT_STATUS_POST_RESTART=`cat {INSTALL_HOME}/tmp/bwagent_status_post_$(whoami).txt |tail -1 |awk -F" " '{print $2}'`
			echo "`date +"%m-%d-%Y-%T"` -Status of bwagent post restart is $BWAGENT_STATUS_POST_RESTART, check finished for pid $x" >>${File_debug}
			echo "`date +"%m-%d-%Y-%T"` - Moving file to ${LOGDIR}/dump" >>${File_debug}
                        `mv $TIBCO_HOME/bw/6.4/bin/java_pid${x}.hprof $LOGDIR/dump/heapdumpfor_java_pid${x}.hprof`
			echo "<tr><td>`hostname`</td><td>$TIBCO_HOME</td><td>$BWAGENT_STATUS_PRE_RESTART</td><td>$BWAGENT_STATUS_POST_RESTART</td></tr>" >> ${File_log}
		fi
	done
	#cat {INSTALL_HOME}/HeapMemCheck/web-part2.html >>${File_log}	
else
        echo "`date +"%m-%d-%Y-%T"` - No dump file found for bwagents " >>${File_debug}
fi

cat {INSTALL_HOME}/HeapMemCheck/web-part3.html >>${File_log}

if [ $EMAIL_SEND -eq 1 ]
        then
                (
                echo To: EAI@company.com
                echo Cc: prem.sri@comapny.com
                echo From: EAI_SUPPORT
                echo "Content-Type: text/html;"
                echo Subject: AppNode Status  Exception found on `hostname`
                cat ${File_mail}
                ) | /usr/sbin/sendmail -t

fi
