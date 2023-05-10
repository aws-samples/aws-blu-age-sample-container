#! /bin/bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Trace
SETX=0
if [ "$SETX" -eq 1 ]; then
        set -x
fi

#####################################################################################
## Variables.
#####################################################################################

LOG_DIRECTORY="/tmp/bluage-logs"
BASE_DIR=$(pwd)

#####################################################################################
## Functions.
#####################################################################################

# Log Function - outputs neatly formatted message including date/time and calling function.
#  Output to stdout and to disk
function log() {

  local __func=$1
  local __msg=$2

  if [ ! -d ${LOG_DIRECTORY} ] ; then
    mkdir -p ${LOG_DIRECTORY}/upload
  fi

  printf "[%s] %-25.25s %s\n" "$(date '+%d/%m/%Y %H:%M:%S:%3N')" "[${__func}]" "${__msg}" 2>&1 | tee -a ${LOG_DIRECTORY}/upload/${0##*/}.log

}

# This function is designed to check the runtime environment is ready and fail fast if not
# These sample environment variables should be updated as required
function check_environment () {

  log ${FUNCNAME[0]} "Checking environment variables"

  # Check whether an Aurora RDS is available via an environment variable
  # Uncomment the exit statement to enable forced exits
  log ${FUNCNAME[0]} "RDS_ENDPOINT $RDS_ENDPOINT"
  if [ "$DB_PASSWORD" != "" ];
  then 
    log ${FUNCNAME[0]} "Database Credentials Found"
  else
    log ${FUNCNAME[0]} "Database Credentials missing - exiting"
    #exit 1
  fi

  # Allow the database name to be configured at runtime
  if [ "$DB_NAME" != "" ];
  then
    log ${FUNCNAME[0]} "Database Name found $DB_NAME"
  else
    log ${FUNCNAME[0]} "Database Name missing, reverting to default value (bluage_db)"
    DB_NAME="bluage_db"
  fi

  # Supply the Java Heap configuration at runtime
  if [ "$JAVA_MAX_HEAP" != "" ];
  then
    log ${FUNCNAME[0]} "Java Heap Maximum Found $JAVA_MAX_HEAP"
  else
    log ${FUNCNAME[0]} "Java Heap Maximum missing, reverting to default value (empty string, using system default)"
  fi

  # Enable debug logging
  # Note the logging string here is a sample and will need to be customised on a per customer basis
  if [ "$DEBUG_ENABLED" == "TRUE" ];
  then
    log ${FUNCNAME[0]} "Enabling debug logging"
    set -x
    LOGGING_STRING="-Dlogging.level.org.springframework=INFO -Dlogging.level.org.springframework.beans.factory.support.DefaultListableBeanFactory=WARN -Dlogging.level.org.springframework.statemachine=WARN -Dlogging.level.org.springframework.jdbc.core.JdbcTemplate=TRACE -Dlogging.level.org.springframework.jdbc.core.StatementCreatorUtils=TRACE -Dlogging.level.org.springframework.jdbc.support.SQLErrorCodesFactory=INFO -Dlogging.level.com.netfective.bluage.gapwalk.database.support.logging.DatabaseInteractionLoggerUtils=TRACE -Dlogging.level.com.netfective.bluage.gapwalk.database.support.AbstractDatabaseSupport=DEBUG -Dlogging.level.com.netfective.bluage.gapwalk.utility=DEBUG"
    log ${FUNCNAME[0]} "Logging Configuration: $LOGGING_STRING"
  else
    log ${FUNCNAME[0]} "Using standard logging level"
    LOGGING_STRING="-Dlogging.level.com.netfective.bluage.gapwalk.utility=DEBUG"
  fi

  # Allow the job execution time to be fixed to a specific point
  # This can be used to execute tests that produce consistent outputs which may be compared against mainframe outputs
  if [ "$FIXED_EXPORT_TIME" != "" ];
  then
    log ${FUNCNAME[0]} "Found a fixed time for the batch execution: $FIXED_EXPORT_TIME"
  else
    log ${FUNCNAME[0]} "Fixed timestamp for execution is missing, using default value (empty string)"
  fi

  # Override the JDBC parameters appended to the connection string
  if [ "$JDBC_PARAMETERS" != "" ];
  then
    log ${FUNCNAME[0]} "Using supplied JDBC parameters: $JDBC_PARAMETERS"
  else
    log ${FUNCNAME[0]} "JDBC parameters were not supplied, using default value (defaultRowFetchSize=1000)"
  fi

  # Print the source and output S3 buckets for the task 
  log ${FUNCNAME[0]} "S3_INPUT_BUCKET $S3_INPUT_BUCKET"
  log ${FUNCNAME[0]} "S3_OUTPUT_BUCKET $S3_OUTPUT_BUCKET"

  # Print the IAM role being used by the container
  #log ${FUNCNAME[0]} "Printing AWS identity"
  #log ${FUNCNAME[0]} "$(aws sts get-caller-identity)"

}

# This function uses the built-in pg_isready binary to verify the network connectivity to an Aurora PostgreSQL instance
# Uncomment the exit statement to enable forced exits
function verify_db_connection () {

  local __retcode=""

  log ${FUNCNAME[0]} "Testing connection to RDS_ENDPOINT $RDS_ENDPOINT"
  pg_isready -h $RDS_ENDPOINT -p 5432
  __retcode=$?
  if [ "$__retcode" -ne 0 ];
  then
    log ${FUNCNAME[0]} "Failed to connect to postgreSQL - exiting"
    #exit 1
  fi

}

# The logs from Blu Age applications in debug mode can be very large (GB).
# This function will split a large log file into smaller chunks before zipping and uploading to S3
function process_log_file () {

  local __filename=$1
  local __s3_bucket=$2
  local __module=$3
  local __zipname="logs-$(date +'%Y%m%dT%H%M').zip"

  log ${FUNCNAME[0]} "Splitting log file ${LOG_DIRECTORY}/${__filename} into 50mb chunks"
  cd ${LOG_DIRECTORY}/upload
  split ${LOG_DIRECTORY}/${__filename} split_log_file -b 50m -d -a 5

  log ${FUNCNAME[0]} "Zipping log files for transfer"
  zip ${LOG_DIRECTORY}/${__zipname} split_log_file*
  zip ${LOG_DIRECTORY}/${__zipname} wrapper.sh.log

  log ${FUNCNAME[0]} "Uploading archive to S3"
  aws s3 cp ${LOG_DIRECTORY}/${__zipname} s3://$__s3_bucket/$__module/logs/

}

# This is the main logic which is used to execute a batch job task with Blu Age
function batch_execution () {

  local __module=$1
  local __s3_bucket=$2
  local __retcode=""
  local __filecount=0
  local __logname="debug-${__module}-$(date +'%Y%m%dT%H%M').log"

  # Module in this example corresponds with the mainframe job which has been modernised
  # The single generated jar will likely contain the code for multiple mainframe JCLs
  log ${FUNCNAME[0]} "Running batch data extraction for module $__module"

  cd /usr/share/bluage

  # Create checkpoint file to timestamp all files present before the modernised application runs
  # This allows us to differentiate input files from generated output files
  touch find_after

  # Set pipefail to ensure that piping the output to tee won't hide the java return code
  set -o pipefail

  # Run batch task process, trigger log upload to S3 automatically upon failure (debug logs are too large to reasonably interrogate via CloudWatch)
  java -Dspring.datasource.url=jdbc:postgresql://${RDS_ENDPOINT}:5432/${DB_NAME}?${JDBC_PARAMETERS} -Dspring.datasource.username=bluage -Dspring.datasource.password=${DB_PASSWORD} ${JAVA_MAX_HEAP} ${LOGGING_STRING} -jar bluAgeSample.jar --module=${__module} ${FIXED_EXPORT_TIME} 2>&1 | tee -a ${LOG_DIRECTORY}/${__logname}
  __retcode=$?
  if [ "$__retcode" -ne 0 ];
  then
    log ${FUNCNAME[0]} "Exception thrown executing Java process"
    log ${FUNCNAME[0]} "Uploading debug log to S3"
    process_log_file $__logname $__s3_bucket $__module
    ls -lart /usr/share/bluage
    exit 1
  fi

  ls -lart /usr/share/bluage

  # Remove temporary files generated at runtime
  find -type f -newer find_after -regex '^.*&&.*$' -exec rm -f {} \;
  find -type f -newer find_after -regex '^.*groovy' -exec rm -f {} \;  

  # Copy files created after the "find_after" checkpoint file to the output folder
  mkdir /usr/share/bluage/output
  find . -type f -newer find_after -exec mv {} output/ \;

  __filecount=$(ls -1q /usr/share/bluage/output/ | wc -l)

  # If debug is enabled, upload the application log output
  if [ "$DEBUG_ENABLED" == "TRUE" ];
  then
    process_log_file $__logname $__s3_bucket $__module
  fi

  if [ "$__filecount" -eq 0 ];
  then
    log ${FUNCNAME[0]} "Java process did not generate any output files"
    exit 1
  else
    log ${FUNCNAME[0]} "Java process generated $__filecount files"
    ls -1q /usr/share/bluage/output
  fi  

  log ${FUNCNAME[0]} "Batch complete"
}

# This is the main logic which is used to start a real time service from Blu Age
function realtime_execution () {

  local __module=$1
  local __retcode=""

  log ${FUNCNAME[0]} "Running realtime ECS Service"
  cd /usr/share/bluage

  # Run online process - this should not exit
  java -Dspring.datasource.url=jdbc:postgresql://${RDS_ENDPOINT}:5432/${DB_NAME}?${JDBC_PARAMETERS} -Dspring.datasource.username=bluage -Dspring.datasource.password=${DB_PASSWORD} ${JAVA_MAX_HEAP} ${LOGGING_STRING} -jar bluAgeSample.jar --module=${__module} ${FIXED_EXPORT_TIME}
  __retcode=$?
  if [ "$__retcode" -ne 0 ];
  then
    log ${FUNCNAME[0]} "Exception thrown executing Java process"
    exit 1
  fi
  log ${FUNCNAME[0]} "Java process exited, this is unexpected"

}

# This function is used to copy input files from S3 into the container working directory
#
# This assumes the following input hierarchy:
#
#  ┌─────────────┐
#  │  $S3Bucket  │
#  └──┬──────────┘
#     │    ┌───────┐
#     ├────┤$Module│
#     │    └─┬─────┘
#     │      │     ┌──────┐
#     │      ├─────┤inputs│
#     │      │     └──────┘
#     │      │     ┌──────┐
#     │      └─────┤params│
#     │            └──────┘
#     │    ┌──────┐
#     └────┤common│
#          └─┬────┘
#            │     ┌──────┐
#            └─────┤params│
#                  └──────┘

function get_input_files () {

  local __module=$1
  local __s3_bucket=$2
  local __retcode=""

  log ${FUNCNAME[0]} "Retrieving files for $__module from s3://$__s3_bucket/"

  mkdir -p /usr/share/bluage
  aws s3 cp s3://$__s3_bucket/$__module/params/ /usr/share/bluage/ --recursive
  __retcode=$?
  if [ "$__retcode" -ne 0 ];
  then
    log ${FUNCNAME[0]} "Failed to retrieve module parameter files from S3 - exiting"
    exit 1
  fi

  aws s3 cp s3://$__s3_bucket/$__module/inputs/ /usr/share/bluage/ --recursive
  __retcode=$?
  if [ "$__retcode" -ne 0 ];
  then
    log ${FUNCNAME[0]} "Failed to retrieve module input files from S3 - exiting"
    exit 1
  fi

  aws s3 cp s3://$__s3_bucket/common/params/ /usr/share/bluage/ --recursive
  __retcode=$?
  if [ "$__retcode" -ne 0 ];
  then
    log ${FUNCNAME[0]} "Failed to retrieve common parameter files from S3 - exiting"
    exit 1
  fi
}

# This function copies job output files into S3
function send_output_file () {
  local __module=$1
  local __s3_output_bucket=$2
  local __s3_input_bucket=$3 
  local __retcode=""
  local __timestamp=$(date +%Y-%m-%d)

  # Store a timestamped copy of the output for archival purposes
  log ${FUNCNAME[0]} "Archiving output files for $__module to s3://$__s3_output_bucket/$__module/archive/$__timestamp"
  aws s3 cp /usr/share/bluage/output/ s3://$__s3_output_bucket/$__module/archive/$__timestamp/ --recursive
  __retcode=$?
  if [ "$__retcode" -ne 0 ];
  then
    log ${FUNCNAME[0]} "Failed to upload output files into S3 archive - exiting"
    exit 1
  fi

  # Send the output to S3
  log ${FUNCNAME[0]} "Sending output files for $__module to s3://$__s3_output_bucket/$__module/outputs/"
  aws s3 cp /usr/share/bluage/output/ s3://$__s3_output_bucket/$__module/outputs/ --recursive
  __retcode=$?
  if [ "$__retcode" -ne 0 ];
  then
    log ${FUNCNAME[0]} "Failed to upload output files into S3 - exiting"
    exit 1
  fi

}

#####################################################################################
## Main.
#####################################################################################

if [ "BATCH" == "$1" ]
then
  check_environment
  verify_db_connection
  get_input_files $2 $3
  batch_execution $2 $4
  send_output_file $2 $4 $3

elif [ "REALTIME" == "$1" ]
then
  verify_db_connection
  realtime_execution online
else
  log "main" "Unsupported or missing execution type supplied"
fi

