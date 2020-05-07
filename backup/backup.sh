#!/bin/sh

#######
### mailcow backup using borgbackup
### this assumes three things:
###     1. standard mailcow-dockerized setup as per the docs
###     2. using borg to perform backups to ssh-capable remote server
###     3. remote repo already set-up and configured
#######


### text formatting presents
if command -v tput > /dev/null; then
    bold=$(tput bold)
    cyan=$(tput setaf 6)
    err=$(tput bold)$(tput setaf 1)
    magenta=$(tput setaf 5)
    norm=$(tput sgr0)
    ok=$(tput setaf 2)
    warn=$(tput bold)$(tput setaf 3)
    width=$(tput cols)
    yellow=$(tput setaf 3)
else
    bold=""
    cyan=""
    err=""
    magenta=""
    norm=""
    ok=""
    warn=""
    width=80
    yellow=""
fi


### trap
trap trapExit 1 2 3 6


### functions

# bad configuration value passed in details file
badDetails() {
    if [ "$1" = "empty" ]; then
        exitError 130 "details:${2} cannot be NULL (undefined)"
    elif [ "$1" = "dne" ]; then
        exitError 131 "details:${2} file or directory does not exist."
    fi
}

# bad parameter passed to script
badParam() {
    if [ "$1" = "dne" ]; then
        printf "\n%sError: '%s %s'\n" "$err" "$2" "$3"
        printf "file or directory does not exist.%s\n\n" "$norm"
        exit 1
    elif [ "$1" = "empty" ]; then
        printf "\n%sError: '%s' cannot have a NULL (empty) value.\n" "$err" "$2"
        printf "%sPlease use '--help' for assistance%s\n\n" "$cyan" "$norm"
        exit 1
    elif [ "$1" = "svc" ]; then
        printf "\n%sError: '%s %s': Service does not exist!%s\n\n" \
            "$err" "$2" "$3" "$norm"
        exit 1
    elif [ "$1" = "user" ]; then
        printf "\n%sError: '%s %s': User does not exist!%s\n\n" \
            "$err" "$2" "$3" "$norm"
        exit 1
    fi
}

# cleanup
cleanup() {
    # cleanup 503 if copied
    if [ "$err503Copied" -eq 1 ]; then
        if ! rm -f "$webroot/$err503File" 2>>"$logFile"; then
            printf "%s[%s] -- [WARNING] Could not remove 503 error page." \
                "$warn" "$(stamp)" >> "$logFile"
            printf " Web interface will not function until this file is " \
                >> "$logFile"
            printf "removed --%s\n" "$norm" >> "$logFile"
            warnCount=$((warnCount+1))
        else
            printf "%s[%s] -- [INFO] 503 error page removed --%s\n" \
                "$cyan" "$(stamp)" "$norm" >> "$logFile"
        fi        
    fi
    # cleanup SQL dump directory if created
    if [ "$sqlDumpDirCreated" -eq 1 ]; then
        if ! rm -rf "$sqlDumpDir" 2>>"$logFile"; then
            printf "%s[%s] -- [WARNING] Could not remove temporary SQL-dump directory. Sorry for the mess. --%s\n" \
                "$warn" "$(stamp)" "$norm" >> "$logFile"
        else
            printf "%s[%s] -- [INFO] Temporary SQL-dump directory removed successfully --%s\n" \
                "$cyan" "$(stamp)" "$norm" >> "$logFile"
        fi
    fi
    # start docker containers (no harm if they are already running)
    doDocker start postfix
    if [ "$dockerResultState" = "true" ]; then
        printf "%s[%s] -- [INFO] POSTFIX container is running --%s\n" \
            "$cyan" "$(stamp)" "$norm" >> "$logFile"
    else
        exitError 102 'Could not start POSTFIX container.'
    fi
    doDocker start dovecot
    if [ "$dockerResultState" = "true" ]; then
        printf "%s[%s] -- [INFO] DOVECOT container is running --%s\n" \
            "$cyan" "$(stamp)" "$norm" >> "$logFile"
    else
        exitError 102 'Could not start DOVECOT container.'
    fi
}

doDocker() {
    containerName="$( docker ps -a --format '{{ .Names }}' --filter name=${COMPOSE_PROJECT_NAME}_${2}-mailcow_1 )"

    # determine action to take
    if [ "$1" = "stop" ]; then
        printf "%s[%s] -- [INFO] Stopping %s-mailcow container --%s\n" \
            "$cyan" "$(stamp)" "$2" "$norm" >> "$logFile"
        docker-compose -f "$mcDockerCompose" stop --timeout "$dockerStopTimeout" "$2-mailcow" 2>> "$logFile"
        # set result vars
        dockerResultState="$( docker inspect -f '{{ .State.Running }}' $containerName )"
        dockerResultExit="$( docker inspect -f '{{ .State.ExitCode }}' $containerName )"
    elif [ "$1" = "start" ]; then
        printf "%s[%s] -- [INFO] Starting %s-mailcow container --%s\n" \
            "$cyan" "$(stamp)" "$2" "$norm" >> "$logFile"
        docker-compose -f "$mcDockerCompose" start "$2-mailcow" 2>> "$logFile"
        # set result vars
        dockerResultState="$( docker inspect -f '{{ .State.Running }}' $containerName )"
    fi
}

# call cleanup and then exit with error report
exitError() {
    printf "%s[%s] -- [ERROR] %s: %s --%s\n" \
            "$err" "$(stamp)" "$1" "$2" "$norm" >> "$logFile"
    cleanup
    # note script completion with error
    printf "%s[%s] --- %s execution completed with error ---%s\n" \
        "$err" "$(stamp)" "$scriptName" "$norm" >> "$logFile"
    exit "$1"
}

# display script help information
scriptHelp() {
    newline
    printf "%sUsage: %s [parameters]%s\n\n" "$bold" "$scriptName" "$norm"
    textblock "There are NO mandatory parameters. If a parameter is not supplied, its default value will be used. In the case of a switch parameter, it will remain DEactivated if NOT specified."
    newline
    textblock "Switches are listed then followed by a description of their effect on the following line. Finally, if a default value exists, it will be listed on the next line in (parentheses)."
    newline
    textblock "${magenta}--- script related parameters ---${norm}"
    newline
    switchTextblock "-c | --config | --details"
    textblock "Path to the configuration key/value-pair file for this script."
    defaultsTextblock "(scriptPath/scriptName.details)"
    newline
    switchTextblock "-h | -? | --help"
    textblock "This help screen"
    newline
    switchTextblock "-l | --log"
    textblock "Path to write log file"
    defaultsTextblock "(scriptPath/scriptName.log)"
    newline
    switchTextblock "[SWITCH] -v | --verbose"
    textblock "Log borg output with increased verbosity (list all files). Careful! Your log file can get very large very quickly!"
    defaultsTextblock "(normal output, option is OFF)"
    newline
    textblock "${magenta}--- 503 functionality ---${norm}"
    newline
    switchTextblock "[SWITCH] -5 | --use-503"
    textblock "Copy an 'error 503' page/indicator file to your webroot for your webserver to find. Specifying this option will enable other 503 options."
    defaultsTextblock "(do NOT copy, option is OFF)"
    newline
    switchTextblock "--503-path"
    textblock "Path to the file you want copied to your webroot as the 'error 503' page."
    defaultsTextblock "(scriptPath/503_backup.html)"
    newline
    switchTextblock "-w | --webroot"
    textblock "Path to where the 'error 503' file should be copied."
    defaultsTextblock "(/usr/share/nginx/html/)"
    newline
    textblock "More details and examples of script usage can be found in the repo wiki at ${yellow}https://git.asifbacchus.app/asif/myGitea/wiki${norm}"
    newline
}

# generate dynamic timestamps
stamp() {
    (date +%F" "%T)
}

textblock() {
    printf "%s\n" "$1" | fold -w "$width" -s
}

defaultsTextblock() {
    printf "%s%s%s\n" "$yellow" "$1" "$norm"
}

switchTextblock() {
    printf "%s%s%s\n" "$cyan" "$1" "$norm"
}

# print a blank line
newline() {
    printf "\n"
}

# same as exitError but for signal captures
trapExit() {
    printf "%s[%s] -- [ERROR] 99: Caught signal --%s\n" \
            "$err" "$(stamp)" "$norm" >> "$logFile"
    cleanup
    # note script completion with error
    printf "%s[%s] --- %s execution was terminated via signal ---%s\n" \
        "$err" "$(stamp)" "$scriptName" "$norm" >> "$logFile"
    exit 99
}

### end of functions


### default variable values

## script related
# store logfile in the same directory as this script file using the same file
# name as the script but with the extension '.log'
scriptPath="$( CDPATH='' cd -- "$( dirname -- "$0" )" && pwd -P )"
scriptName="$( basename "$0" )"
logFile="$scriptPath/${scriptName%.*}.log"
warnCount=0
configDetails="$scriptPath/${scriptName%.*}.details"
err503Copied=0
exclusions=0
# borg output verbosity -- normal
borgCreateParams='--stats'
borgPruneParams='--list'

# 503 related
use503=0
err503Path="$scriptPath/503_backup.html"
err503File="${err503Path##*/}"
webroot="/usr/share/nginx/html"

# mailcow/docker related
mcConfig='/opt/mailcow-dockerized/mailcow.conf'
mcDockerCompose="${mcConfig%/*}/docker-compose.yml"
dockerStartTimeout=180
dockerStopTimeout=120


### process startup parameters
while [ $# -gt 0 ]; do
    case "$1" in
        -h|-\?|--help)
            # display help
            scriptHelp
            exit 0
            ;;
        -l|--log)
            # set log file location
            if [ -n "$2" ]; then
                logFile="${2%/}"
                shift
            else
                badParam empty "$@"
            fi
            ;;
        -c|--config|--details)
            # location of config details file
            if [ -n "$2" ]; then
                if [ -f "$2" ]; then
                    configDetails="${2%/}"
                    shift
                else
                    badParam dne "$@"
                fi
            else
                badParam empty "$@"
            fi
            ;;
        -v|--verbose)
            # set verbose logging from borg
            borgCreateParams='--list --stats'
            borgPruneParams='--list'
            ;;
        -5|--use-503)
            # enable copying 503 error page to webroot
            use503=1
            ;;
        --503-path)
            # FULL path to 503 file
            if [ -n "$2" ]; then
                if [ -f "$2" ]; then
                    err503Path="${2%/}"
                    err503File="${2##*/}"
                    shift
                else
                    badParam dne "$@"
                fi
            else
                badParam empty "$@"
            fi
            ;;
        -w|--webroot)
            # path to webroot (copy 503)
            if [ -n "$2" ]; then
                if [ -d "$2" ]; then
                    webroot="${2%/}"
                    shift
                else
                    badParam dne "$@"
                fi
            else
                badParam empty "$@"
            fi
            ;;
        -d|--docker-compose)
            # path to mailcow docker-compose file
            if [ -n "$2" ]; then
                if [ -f "$2" ]; then
                    mcDockerCompose="${2%/}"
                    shift
                else
                    badParam dne "$@"
                fi
            else
                badParam empty "$@"
            fi
            ;;
        -m|--mailcow-config)
            # path to mailcow configuration file
            if [ -n "$2" ]; then
                if [ -f "$2" ]; then
                    mcConfig="${2%/}"
                    shift
                else
                    badParam dne "$@"
                fi
            else
                badParam empty "$@"
            fi
            ;;
        -t1|--timeout-start)
            if [ -z "$2" ]; then
                badParam empty "$@"
            else
                dockerStartTimeout="$2"
            fi
            ;;
        -t2|--timeout-stop)
            if [ -z "$2" ]; then
                badParam empty "$@"
            else
                dockerStopTimeout="$2"
            fi
            ;;
        *)
            printf "\n%sUnknown option: %s\n" "$err" "$1"
            printf "%sUse '--help' for valid options.%s\n\n" "$cyan" "$norm"
            exit 1
            ;;
    esac
    shift
done


### check pre-requisites and default values
# check if running as root, otherwise exit
if [ "$( id -u )" -ne 0 ]; then
    printf "\n%sERROR: script MUST be run as ROOT%s\n\n" "$err" "$norm"
    exit 2
fi
# does the details file exist?
if [ ! -f "$configDetails" ]; then
    badParam dne "(--details default)" "$configDetails"
fi
# is borg installed?
if ! command -v borg > /dev/null; then
    printf "\n%sERROR: BORG is not installed on this system!%s\n\n" "$err" "$norm"
    exit 3
fi
# if 503 functionality is enabled, do 503 related files exist?
if [ "$use503" -eq 1 ]; then
    if [ ! -f "$err503Path" ]; then
        badParam dne "(--503-path default)" "$err503Path"
    elif [ ! -d "$webroot" ]; then
        badParam dne "(--webroot default)" "$webroot"
    fi
fi
# verify mailcow.conf location and extract path
if [ ! -f "$mcConfig" ]; then
    badParam dne "(--mailcow-config)" "$mcConfig"
fi
# verify docker-compose file exists
if [ ! -f "$mcDockerCompose" ]; then
    badParam dne "(--docker-compose)" "$mcDockerCompose"
fi


### read mailcow.conf and set vars as needed
. "$mcConfig"
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export COMPOSE_HTTP_TIMEOUT="$dockerStartTimeout"


### start logging
printf "%s[%s] --- Start %s execution ---%s\n" \
    "$magenta" "$(stamp)" "$scriptName" "$norm" >> "$logFile"
printf "%s[%s] -- [INFO] Log located at %s%s%s --%s\n" \
    "$cyan" "$(stamp)" "$yellow" "$logFile" "$cyan" "$norm" >> "$logFile"


### get location of docker volumes
dockerVolumeMail=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_vmail-vol-1)
printf "%s[%s] -- [INFO] Using MAIL volume: %s --%s\n" \
    "$cyan" "$(stamp)" "$dockerVolumeMail" "$norm" >> "$logFile"
dockerVolumeRspamd=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_rspamd-vol-1)
printf "%s[%s] -- [INFO] Using RSPAMD volume: %s --%s\n" \
    "$cyan" "$(stamp)" "$dockerVolumeRspamd" "$norm" >> "$logFile"
dockerVolumePostfix=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_postfix-vol-1)
printf "%s[%s] -- [INFO] Using POSTFIX volume: %s --%s\n" \
    "$cyan" "$(stamp)" "$dockerVolumePostfix" "$norm" >> "$logFile"
dockerVolumeRedis=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_redis-vol-1)
printf "%s[%s] -- [INFO] Using REDIS volume: %s --%s\n" \
    "$cyan" "$(stamp)" "$dockerVolumeRedis" "$norm" >> "$logFile"
dockerVolumeCrypt=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_crypt-vol-1)
printf "%s[%s] -- [INFO] Using MAILCRYPT volume: %s --%s\n" \
    "$cyan" "$(stamp)" "$dockerVolumeCrypt" "$norm" >> "$logFile"


### read details file to get variables needed run borg
# check if config details file was provided as a relative or absolute path
case "${configDetails}" in
    /*)
        # absolute path, no need to rewrite variable
        . "${configDetails}"
        ;;
    *)
        # relative path, prepend './' to create absolute path
        . "./${configDetails}"
        ;;
esac
printf "%s[%s] -- [INFO] %s%s%s imported --%s\n" \
    "$cyan" "$(stamp)" "$yellow" "$configDetails" "$cyan" "$norm" >> "$logFile"


### Run borg variable checks
printf "%s[%s] -- [INFO] Verifying supplied borg details --%s\n" \
    "$cyan" "$(stamp)" "$norm" >> "$logFile"

## read additional files -- this is required otherwise nothing to backup!
if [ -z "${borgXtraListPath}" ]; then
    badDetails empty 'xtraLocations'
else
    # check if file actually exists
    if [ ! -f "${borgXtraListPath}" ]; then
        badDetails dne 'borgXtraListPath'
    fi
    # read file contents into concatenated list for echo to cmdline
    while read -r xtraItem; do
        if [ -z "${xtraList}" ]; then
            xtraList="${xtraItem}"
        else
            xtraList="${xtraList} ${xtraItem}"
        fi
    done <<EOF
    $( sed -e '/^\s*#.*$/d' -e '/^\s*$/d' "${borgXtraListPath}" )
EOF
printf "%sdetails:borgXtraListPath %s-- %s[OK]%s\n" \
    "$magenta" "$norm" "$ok" "$norm" >> "$logFile"
fi

## verify borg base directory
if [ -z "${borgBaseDir}" ]; then
    badDetails empty 'borgBaseDir'
elif [ ! -d "${borgBaseDir}" ]; then
    badDetails dne 'borgBaseDir'
fi
printf "%sdetails:borgBaseDir %s-- %s[OK]%s\n" \
    "$magenta" "$norm" "$ok" "$norm" >> "$logFile"
export BORG_BASE_DIR="${borgBaseDir%/}"

## check path to SSH keyfile
if [ -z "${borgSSHKey}" ]; then
    badDetails empty 'borgSSHKey'
elif [ ! -f "${borgSSHKey}" ]; then
    badDetails dne 'borgSSHKey'
fi
printf "%sdetails:borgSSHKey %s-- %s[OK]%s\n" \
    "$magenta" "$norm" "$ok" "$norm" >> "$logFile"
export BORG_RSH="ssh -i ${borgSSHKey}"

## check borg repo connect string
if [ -z "${borgConnectRepo}" ]; then
    badDetails empty 'borgConnectRepo'
fi
printf "%sdetails:borgConnectRepo %s-- %s[OK]%s\n" \
    "$magenta" "$norm" "$ok" "$norm" >> "$logFile"
export BORG_REPO="${borgConnectRepo}"

## check borg repo password
if [ -n "${borgRepoPassphrase}" ]; then
    printf "%sdetails:borgRepoPassphrase %s-- %s[OK]%s\n" \
    "$magenta" "$norm" "$ok" "$norm" >> "$logFile"
    export BORG_PASSPHRASE="${borgRepoPassphrase}"
else
    # if passwd is blank intentionally, this is insecure
    printf "%s-- [WARNING] Using a borg repo without a password is an " \
        "$warn" >> "$logFile"
    printf "insecure configuration --%s\n" "$norm">> "$logFile"
    warnCount=$((warnCount+1))
    # if this was an accident, we need to provide a bogus passwd so borg fails
    # otherwise it will sit forever just waiting for input
    export BORG_PASSPHRASE="DummyPasswordSoBorgFails"
fi

## check borg repository keyfile location
if [ -z "${borgKeyfileLocation}" ]; then
    printf "%sdetails:borgKeyfileLocation %s-- %s[DEFAULT]%s\n" "$magenta" "$norm" "$ok" "$norm" >> "$logFile"
else
    # check if keyfile location exists
    if [ ! -f "${borgKeyfileLocation}" ]; then
        badDetails dne 'borgKeyfileLocation'
    fi
    printf "%sdetails:borgKeyfileLocation %s-- %s[OK]%s\n" "$magenta" "$norm" "$ok" "$norm" >> "$logFile"
    export BORG_KEY_FILE="${borgKeyfileLocation}"
fi

## export borg remote path, if specified
if [ -n "${borgRemote}" ]; then export BORG_REMOTE_PATH="${borgRemote}"; fi

## check if exlusion list file is specified
if [ -n "${borgExcludeListPath}" ]; then
    # check if the file actually exists
    if [ ! -f "${borgExcludeListPath}" ]; then
        badDetails dne 'borgExcludeListPath'
    fi
exclusions=1
fi


### set location of sql dump
# this is done before resetting default TMP dir for borg
if ! sqlDumpDir=$( mktemp -d 2>/dev/null ); then
    exitError 115 'Unable to create temp directory for SQL dump.'
else
    sqlDumpFile="backup-$( date +%Y%m%d_%H%M%S ).sql"
    sqlDumpDirCreated=1
    printf "%s[%s] -- [INFO] SQL dump file will be stored at: %s --%s\n" \
        "$cyan" "$(stamp)" "$sqlDumpDir/$sqlDumpFile" "$norm" >> "$logFile"
fi


### create borg temp dir:
## python requires a writable temporary directory when unpacking borg and
## executing commands.  This defaults to /tmp but many systems mount /tmp with
## the 'noexec' option for security.  Thus, we will use/create a 'tmp' folder
## within the BORG_BASE_DIR and instruct python to use that instead of /tmp

# check if BORG_BASE_DIR/tmp exists, if not, create it
if [ ! -d "${borgBaseDir}/tmp" ]; then
    if ! mkdir "${borgBaseDir}/tmp"; then
        exitError 132 "Unable to create borg ${borgBaseDir}/tmp directory"
    else
        printf "%s[%s] -- [INFO] Created %s%s/tmp " \
            "$cyan" "$(stamp)" "$yellow" "${borgBaseDir}" >> "$logFile"
        printf "%s--%s\n" "$cyan" "$norm">> "$logFile"
    fi
fi
export TMPDIR="${borgBaseDir}/tmp"


### 503 functionality
if [ "$use503" -eq 1 ]; then
    printf "%s[%s] -- [INFO] Copying 503 error page to " \
        "$cyan" "$(stamp)" >> "$logFile"
    printf "webroot -- %s\n" "$norm">> "$logFile"
    if ! cp --force "${err503Path}" "${webroot}/${err503File}" 2>> "$logFile"
        then
        printf "%s[%s] -- [WARNING] Failed to copy 503 error page. " \
            "$warn" "$(stamp)" >> "$logFile"
        printf "Web users will NOT be notified --%s\n" "$norm" >> "$logFile"
        warnCount=$((warnCount+1))
    else
        printf "%s[%s] -- [SUCCESS] 503 error page copied --%s\n" \
            "$ok" "$(stamp)" "$norm" >> "$logFile"
        # set cleanup flag
        err503Copied=1
    fi
fi

### change to mailcow directory so docker commands execute properly
cd "${mcConfig%/*}" || exitError 100 'Could not change to mailcow directory.'

### stop postfix and dovecot mail containers to prevent mailflow during backup
doDocker stop postfix
if [ "$dockerResultState" = "false" ] && [ "$dockerResultExit" -eq 0 ]; then
    printf "%s[%s] -- [INFO] POSTFIX container stopped --%s\n" \
        "$cyan" "$(stamp)" "$norm" >> "$logFile"
else
    exitError 101 'Could not stop POSTFIX container.'
fi
doDocker stop dovecot
if [ "$dockerResultState" = "false" ] && [ "$dockerResultExit" -eq 0 ]; then
    printf "%s[%s] -- [INFO] DOVECOT container stopped --%s\n" \
        "$cyan" "$(stamp)" "$norm" >> "$logFile"
else
    exitError 101 'Could not stop DOVECOT container.'
fi


### dump SQL
printf "%s[%s] -- [INFO] Dumping mailcow SQL database --%s\n" \
    "$cyan" "$(stamp)" "$norm" >> "$logFile"
docker-compose exec -T mysql-mailcow mysqldump --default-character-set=utf8mb4 \
    -u${DBUSER} -p${DBPASS} ${DBNAME} > "$sqlDumpDir/$sqlDumpFile" 2>> "$logFile"
dumpResult=$( docker-compose exec -T mysql-mailcow echo "$?" )
if [ "$dumpResult" -eq 0 ]; then
    printf "%s[%s] -- [INFO] SQL database dumped successfully --%s\n" \
        "cyan" "$(stamp)" "$norm" >> "$logFile"
else
    exitError 118 'There was an error dumping the mailcow SQL database.'
fi


### dump redis inside container
# delete old redis dump if it exists
if [ -f "$dockerVolumeRedis/dump.rdb" ]; then
    rm -f "$dockerVolumeRedis/dump.rdb"
fi
# dump redis
printf "%s[%s] -- [INFO] Dumping mailcow redis database --%s\n" \
    "$cyan" "$(stamp)" "$norm" >> "$logFile"
docker-compose exec -T redis-mailcow redis-cli save >> "$logFile" 2>&1
rdumpResult=$( docker-compose exec -T redis-mailcow echo "$?" )
if [ "$rdumpResult" -eq 0 ]; then
    printf "%s[%s] -- [INFO] mailcow redis dumped successfully --%s\n" \
        "cyan" "$(stamp)" "$norm" >> "$logFile"
else
    exitError 119 'There was an error dumping the mailcow redis database.'
fi


### execute borg depending on whether exclusions are defined
printf "%s[%s] -- [INFO] Pre-backup tasks completed, calling borgbackup --%s\n" "$cyan" "$(stamp)" "$norm" >> "$logFile"

## construct the proper borg commandline
# base command
if [ "$exclusions" -eq 0 ]; then
    borgCMD="borg --show-rc create ${borgCreateParams} \
        ::$(date +%Y-%m-%d_%H%M%S) \
        ${sqlDumpDir} \
        ${dockerVolumeMail} \
        ${dockerVolumeRspamd} \
        ${dockerVolumePostfix} \
        ${dockerVolumeRedis} \
        ${dockerVolumeCrypt} \
        ${xtraList}"
elif [ "$exclusions" -eq 1 ]; then
    borgCMD="borg --show-rc create ${borgCreateParams} \
        --exclude-from ${borgExcludeListPath} \
        ::$(date +%Y-%m-%d_%H%M%S) \
        ${sqlDumpDir} \
        ${dockerVolumeMail} \
        ${dockerVolumeRspamd} \
        ${dockerVolumePostfix} \
        ${dockerVolumeRedis} \
        ${dockerVolumeCrypt} \
        ${xtraList}"
fi

# execute borg
printf "%s[%s] -- [INFO] Executing borg backup operation --%s\n" \
    "$cyan" "$(stamp)" "$norm" >> "$logFile"
${borgCMD} 2>> "$logFile"
borgResult="$?"

## check borg exit status
if [ "$borgResult" -eq 0 ]; then
    printf "%s[%s] -- [SUCCESS] Borg backup completed --%s\n" \
        "$ok" "$(stamp)" "$norm" >> "$logFile"
elif [ "$borgResult" -eq 1 ]; then
    printf "%s[%s] -- [WARNING] Borg completed with warnings. " \
        "$warn" "$(stamp)" >> "$logFile"
    printf "Review this logfile for details --%s\n" "$norm">> "$logFile"
    warnCount=$((warnCount+1))
elif [ "$borgResult" -ge 2 ]; then
    err_1="Borg exited with a critical error. Please review this log file"
    err_2="for details."
    exitError 138 "$err_1 $err_2"
else
    printf "%s[%s] -- [WARNING] Borg exited with unknown return code. " \
        "$warn" "$(stamp)" >> "$logFile"
    printf "Review this logfile for details --%s\n" "$norm">> "$logFile"
    warnCount=$((warnCount+1))
fi


### execute borg prune if paramters are provided, otherwise skip with a warning
if [ -n "${borgPruneSettings}" ]; then
    printf "%s[%s] -- [INFO] Executing borg prune operation --%s\n" \
        "$cyan" "$(stamp)" "$norm" >> "$logFile"
    borg prune --show-rc -v ${borgPruneParams} ${borgPruneSettings} \
        2>> "$logFile"
    borgPruneResult="$?"
else
    printf "%s[%s] -- [WARNING] No prune parameters provided. " \
        "$warn" "$(stamp)" >> "$logFile"
    printf "Your archive will continue growing with each backup --%s\n" \
        "$norm" >> "$logFile"
    warnCount=$((warnCount+1))
fi

## report on prune operation if executed
if [ -n "${borgPruneResult}" ]; then
    if [ "${borgPruneResult}" -eq 0 ]; then
        printf "%s[%s] -- [SUCCESS] Borg prune completed --%s\n" \
            "$ok" "$(stamp)" "$norm" >> "$logFile"
    elif [ "$borgPruneResult" -eq 1 ]; then
        printf "%s[%s] -- [WARNING] Borg prune completed with warnings. " \
        "$warn" "$(stamp)" >> "$logFile"
        printf "Review this logfile for details --%s\n" "$norm" >> "$logFile"
        warnCount=$((warnCount+1))
    elif [ "$borgPruneResult" -ge 2 ]; then
        err_1="Borg prune exited with a critical error. Please review this"
        err_2="log file for details."
        exitError 139 "$err_1 $err_2"
    else
        printf "%s[%s] -- [WARNING] Borg prune exited with an unknown " \
            "$warn" "$(stamp)" >> "$logFile"
        printf "return code. Review this logfile for details --%s\n" \
            "$norm" >> "$logFile"
        warnCount=$((warnCount+1))
    fi
fi


### all processes successfully completed, cleanup and exit gracefully

# note successful completion of borg commands
printf "%s[%s] -- [SUCCESS] Backup operations completed --%s\n" \
    "$ok" "$(stamp)" "$norm" >> "$logFile"

# cleanup
cleanup

# note complete success, tally warnings and exit
printf "%s[%s] -- [SUCCESS] All processes completed --%s\n" \
    "$ok" "$(stamp)" "$norm" >> "$logFile"
printf "%s[%s] --- %s execution completed ---%s\n" \
    "$magenta" "$(stamp)" "$scriptName" "$norm" >> "$logFile"
if [ "$warnCount" -gt 0 ]; then
    printf "%s%s warnings issued!%s\n" "$warn" "${warnCount}" "$norm" >> "$logFile"
else
    printf "%s0 warnings issued.%s\n" "$ok" "$norm" >> "$logFile"
fi
exit 0


### error codes
# 1: parameter error
# 2: not run as root
# 3: borg not installed
# 99: TERM signal trapped
# 100: could not change to mailcow-dockerized directory
# 101: could not stop container(s)
# 102: could not start container(s)
# 115: unable to create temp dir for SQL dump
# 118: error dumping SQL database
# 119: error dumping redis database
# 130: null configuration variable in details file
# 131: invalid configuration variable in details file
# 138: borg exited with a critical error
# 139: borg prune exited with a critical error