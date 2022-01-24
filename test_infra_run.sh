#!/bin/bash
if [ -z "$TI_PARAM_STR_password" ]; then
    run_mysql_test="/tidb-test/mysqltest --host ${TI_PARAM_STR_host} --user ${TI_PARAM_STR_user} --port ${TI_PARAM_STR_port} --log-level=error"
else
    run_mysql_test="/tidb-test/mysqltest --host ${TI_PARAM_STR_host} --user ${TI_PARAM_STR_user} --passwd ${TI_PARAM_STR_password} --port ${TI_PARAM_STR_port} --log-level=error" 
fi
if [ "$*" ]; then
    run_mysql_test="${run_mysql_test} $*"
fi
${run_mysql_test}
EXIT_CODE=$?

tc_name=$(echo $TI_PARAM_RES_tc | jq -r .name)
testbed=$(echo $TI_PARAM_RES_tc | jq -r .testbed)
tidb_pod=$(/tidb-test/kubectl get pod -n $testbed |grep "tidb" |awk '{print $1}')

/tidb-test/kubectl cp $testbed/$tidb_pod:var/lib/tidb/log ./tidb-log

echo "mysql_test end"
grep 'DATA RACE' ./tidb-log/*.log &>/dev/null
if [ $? -eq 0 ]
then
    echo "ERROR: DATA RACE Found!"
    grep -A 10 -B 20 'DATA RACE' ./tidb-log/*.log
    EXIT_CODE=-2
fi
if [ $EXIT_CODE -ne 0 ]; then
    echo "=========== ERROR EXIT [${EXIT_CODE}]: FULL tidb.log BEGIN ============"
    cat ./tidb-log/*.log
    echo "=========== ERROR EXIT [${EXIT_CODE}]: FULL tidb.log END =============="
fi
exit $EXIT_CODE
