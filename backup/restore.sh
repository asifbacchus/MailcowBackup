#!/bin/sh

#######
### restore mailcow from borgbackup repository
### this assumes three things:
###     1. standard mailcow-dockerized setup as per the docs
###     2. backups made using the backup script from this git repo
###     3. backups already downloaded from your borg repo
#######

### text-formatting presets
if command -v tput >/dev/null; then
    bold=$(tput bold)
    cyan=$(tput bold)$(tput setaf 6)
    err=$(tput bold)$(tput setaf 1)
    info=$(tput sgr0)
    magenta=$(tput sgr0)$(tput setaf 5)
    norm=$(tput sgr0)
    ok=$(tput setaf 2)
    width=$(tput cols)
    yellow=$(tput sgr0)$(tput setaf 3)
else
    bold=''
    cyan=''
    err=''
    info=''
    magenta=''
    norm=''
    ok=''
    width=80
    yellow=''
fi

### trap
trap trapExit 1 2 3 6

### functions

consoleError() {
    printf "\n%s%s\n" "$err" "$2"
    printf "Exiting.\n\n%s" "$norm"
    exit "$1"
}

exitError() {
    printf "%s[%s] --- %s execution completed with error ---\n%s" "$err" "$(stamp)" "$scriptName" "$norm" >> "$logfile"
    exit "$1"
}

doRestore() {
    sourceFiles=$(find "${backupLocation}" -iname "${1}" -type d)
    if [ -n "$sourceFiles" ]; then
        if [ "$verbose" -eq 1 ]; then
            if (! (cd "$sourceFiles/_data" && tar -cf - .) | (cd "${2}" && tar xvf -) >> "$logfile" ); then
                return 1
            else
                return 0
            fi
        else
            if (! (cd "$sourceFiles/_data" && tar -cf - .) | (cd "${2}" && tar xvf -) > /dev/null 2>&1 ); then
                return 1
            else
                return 0
            fi
        fi
    else
        return 2
    fi
}

scriptHelp() {
    textNewline
    printf "%sUsage: %s [parameters]%s\n\n" "$bold" "$scriptName" "$norm"
    textblock "The only required parameter is -b | --backup-location."
    textblock "If a parameter is not supplied, its default value will be used."
    textblock "Switch parameters will only be activated if specified."
    textblockHeader "script parameters"
    textblockParam "-b | --backup-location"
    textblock "Directory containing extracted backup files from borg repo. REQUIRED."
    textNewline
    textblockParam "-l | --log" "scriptPath/scriptName.log"
    textblock "Path to write log file. Best efforts will be made to create any specified paths."
    textNewline
    textblockParam "-v | --verbose" "false"
    textblock "Enable verbose logging. This will list EVERY restored file possibly making your log file quite large! [SWITCH]"
    textNewline
    textblockParam "--skip-mail" "false"
    textblock "Skip restoring mail and encryption key. [SWITCH]"
    textNewline
    textblockParam "--skip-sql" "false"
    textblock "Skip restoring mailcow settings database. [SWITCH]"
    textNewline
    textblockParam "--skip-postfix" "false"
    textblock "Skip restoring postfix settings. [SWITCH]"
    textNewline
    textblockParam "--skip-rspamd" "false"
    textblock "Skip restoring Rspamd settings/configuration/history. [SWITCH]"
    textNewline
    textblockParam "--skip-redis" "false"
    textblock "Skip restoring redis database. [SWITCH]"
    textNewline
    textblockParam "-? | -h | --help"
    textblock "Display this help screen."
    textblockHeader "mailcow parameters"
    textblockParam "-d | --docker-compose" "/opt/mailcow-dockerized/docker-compose.yml"
    textblock "FULL path to mailcow's 'docker-compose.yml' file."
    textNewline
    textblockParam "-m | --mailcow-config" "/opt/mailcow-dockerized/mailcow.conf"
    textblock "FULL path to mailcow configuration file ('mailcow.conf'). The path of this file is also used to determine your mailcow directory."
    textblockHeader "docker parameters"
    textblockParam "-t1 | --timeout-start" "180"
    textblock "Seconds to wait for docker containers to start."
    textNewline
    textblockParam "-t2 | --timeout-stop" "120"
    textblock "Seconds to wait for docker containers to stop."
    textNewline
    textblock "More details and examples of script usage can be found in the repo wiki at ${yellow}https://git.asifbacchus.app/asif/MailcowBackup/wiki${norm}"
    textNewline
    exit 0
}

stamp() {
    (date +%F' '%T)
}

textblock() {
    printf "%s\n" "$1" | fold -w "$width" -s
}

textblockHeader() {
    printf "\n%s%s*** %s ***%s\n\n" "$bold" "$magenta" "$1" "$norm"
}

textblockParam() {
    if [ -z "$2" ]; then
        # no default
        printf "%s%s%s\n" "$cyan" "$1" "$norm"
    else
        # default parameter provided
        printf "%s%s %s(%s)%s\n" "$cyan" "$1" "$yellow" "$2" "$norm"
    fi
}

textNewline() {
    printf "\n"
}

trapExit() {
    printf "%s[%s] -- [ERROR] 99: Caught signal --%s\n" "$err" "$(stamp)" "$norm" >> "$logfile"
    printf "%s[%s] --- %s execution terminated via signal ---\n%s" "$err" "$(stamp)" "$scriptName" "$norm" >> "$logfile"
    exit 99
}

writeLog() {
    if [ "$1" = "task" ]; then
        printf "%s[%s] -- [INFO] %s... " "$info" "$(stamp)" "$2" >> "$logfile"
    elif [ "$1" = "done" ]; then
        if [ -z "$2" ]; then
            printf "%sdone%s --\n%s" "$ok" "$info" "$norm" >> "$logfile"
        elif [ "$2" = "error" ]; then
            printf "%sERROR%s --\n%s" "$err" "$info" "$norm" >> "$logfile"
        elif [ "$2" = "warn" ]; then
            printf "%swarning%s --\n%s" "$yellow" "$info" "$norm" >> "$logfile"
        fi
    elif [ "$1" = "error" ]; then
        printf "%s[%s] -- [ERROR] %s: %s --\n%s" "$err" "$(stamp)" "$2" "$3" "$norm" >> "$logfile"
    elif [ "$1" = "warn" ]; then
        printf "%s[%s] -- [WARNING] %s --\n%s" "$yellow" "$(stamp)" "$2" "$norm" >> "$logfile"
    elif [ "$1" = "info" ]; then
        printf "%s[%s] -- [INFO] %s --\n%s" "$info" "$(stamp)" "$2" "$norm" >> "$logfile"
    elif [ "$1" = "success" ]; then
        printf "%s[%s] -- [SUCCESS] %s --\n%s" "$ok" "$(stamp)" "$2" "$norm" >> "$logfile"
    fi
}

### parameter defaults
# script related
scriptPath="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
scriptName="$(basename "$0")"
errorCount=0
warnCount=0
backupLocation=""
sqlBackup=""
restoreMail=1
restoreSQL=1
restorePostfix=1
restoreRedis=1
restoreRspamd=1
verbose=0
# logfile default: same location and name as script but with '.log' extension
logfile="$scriptPath/${scriptName%.*}.log"
# mailcow/docker related
mcConfig='/opt/mailcow-dockerized/mailcow.conf'
mcDockerCompose='/opt/mailcow-dockerized/docker-compose.yml'
sqlRunning=0
dockerStartTimeout=180
dockerStopTimeout=120

### check if user is root
if [ "$(id -u)" -ne 0 ]; then
    consoleError '2' "This script must be run as ROOT."
fi

### process startup parameters
while [ $# -gt 0 ]; do
    case "$1" in
    -h|-\?|--help)
        # display help
        scriptHelp
        ;;
    -l|--log)
        # set logfile location
        if [ -z "$2" ]; then
            consoleError '1' "Log file path cannot be null. Leave unspecified to save log in the same directory as this script."
        fi
        logfile="$2"
        shift
        ;;
    -v|--verbose)
        verbose=1
        ;;
    -d|--docker-compose)
        # FULL path to docker-compose file
        if [ -n "$2" ]; then
            if [ -f "$2" ]; then
                mcDockerCompose="$2"
                shift
            else
                consoleError '1' "$1: cannot find docker-compose file as specified."
            fi
        else
            consoleError '1' "$1: cannot be blank/empty."
        fi
        ;;
    -m|--mailcow-config)
    # FULL path to mailcow configuration file file
        if [ -n "$2" ]; then
            if [ -f "$2" ]; then
                mcConfig="$2"
                shift
            else
                consoleError '1' "$1: cannot find mailcow configuration file as specified."
            fi
        else
            consoleError '1' "$1: cannot be blank/empty."
        fi
        ;;
    -t1|--timeout-start)
        if [ -z "$2" ]; then
            consoleError '1' "$1: cannot be blank/empty."
        else
            dockerStartTimeout="$2"
            shift
        fi
        ;;
    -t2|--timeout-stop)
        if [ -z "$2" ]; then
            consoleError '1' "$1: cannot be blank/empty."
        else
            dockerStopTimeout="$2"
            shift
        fi
        ;;
    -b|--backup-location)
        if [ -n "$2" ]; then
            if [ -d "$2" ] && [ -n "$( ls -A "$2" )" ]; then
                backupLocation="${2%/}"
                shift
            else
                consoleError '1' "$1: cannot find specified backup location directory or it is empty."
            fi
        else
            consoleError '1' "$1: cannot be blank/empty."
        fi
        ;;
    --skip-mail)
        restoreMail=0
        ;;
    --skip-sql)
        restoreSQL=0
        ;;
    --skip-postfix)
        restorePostfix=0
        ;;
    --skip-redis)
        restoreRedis=0
        ;;
    --skip-rspamd)
        restoreRspamd=0
        ;;
    *)
        printf "\n%sUnknown option: %s\n" "$err" "$1"
        printf "Use '--help' for valid options.%s\n\n" "$norm"
        exit 1
        ;;
    esac
    shift
done

### pre-flight checks
# ensure there's something to do
if [ "$restoreMail" -eq 0 ] && [ "$restoreSQL" -eq 0 ] && [ "$restorePostfix" -eq 0 ] && [ "$restoreRedis" -eq 0 ] && [ "$restoreRedis" -eq 0 ]; then
    printf "\n%sAll restore operations skipped -- nothing to do!%s\n\n" "$yellow" "$norm"
    exit 0
fi
# set path so checks are valid for this script environment
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
# docker installed?
if ! command -v docker >/dev/null; then
    consoleError '3' 'docker does not seem to be installed!'
fi
# mailcow.conf?
if [ ! -f "$mcConfig" ]; then
    consoleError '1' "mailcow configuration file ($mcConfig) cannot be found."
fi
# docker-compose configuration?
if [ ! -f "$mcDockerCompose" ]; then
    consoleError '1' "docker-compose configuration ($mcDockerCompose) cannot be found."
fi
# forgot to set backup location?
if [ -z "$backupLocation" ]; then
    consoleError '1' "'--backup-location' cannot be unspecified or null/empty."
fi
# change to mailcow directory so commands execute properly
\cd "${mcConfig%/*}" || consoleError '4' 'Cannot change to mailcow directory as determined from mailcow.conf location.'

### read mailcow.conf and import vars
# shellcheck source=./mailcow.conf.shellcheck
. "$mcConfig"
export COMPOSE_HTTP_TIMEOUT="$dockerStartTimeout"

### start logging
# verify logfile specification is valid
if ! printf "%s" "$logfile" | grep -o / >/dev/null; then
    # no slashes -> filename provided, save in scriptdir
    logfile="$scriptPath/$logfile"
elif [ "$(printf "%s" "$logfile" | tail -c 1)" = '/' ]; then
    # ends in '/' --> directory provided, does it exist?
    if [ ! -d "$logfile" ]; then
        if ! mkdir -p "$logfile" >/dev/null 2>&1; then
            consoleError '1' "Unable to make specified log file directory."
        fi
    fi
    logdir="$(cd "$logfile" 2>/dev/null && pwd -P)"
    logfile="${logdir}/${scriptName%.*}.log"
else
    # full path provided, does the parent directory exist?
    if [ ! -d "${logfile%/*}" ]; then
        # make parent path
        if ! mkdir -p "${logfile%/*}" >/dev/null 2>&1; then
            consoleError '1' "Unable to make specified log file path."
        fi
    fi
fi
# write initial log entries
if ! printf "%s[%s] --- Start %s execution ---\n%s" "$magenta" "$(stamp)" "$scriptName" "$norm" 2>/dev/null >> "$logfile"; then
    consoleError '1' "Unable to write to log file ($logfile)"
fi
writeLog 'info' "Log located at $logfile"

### get location of docker volumes
dockerVolumeMail=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_vmail-vol-1)
writeLog 'info' "Using MAIL volume: ${dockerVolumeMail}"
dockerVolumeCrypt=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_crypt-vol-1)
writeLog 'info' "Using MAILCRYPT volume: ${dockerVolumeCrypt}"
dockerVolumePostfix=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_postfix-vol-1)
writeLog 'info' "Using POSTFIX volume: ${dockerVolumePostfix}"
dockerVolumeRedis=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_redis-vol-1)
writeLog 'info' "Using REDIS volume: ${dockerVolumeRedis}"
dockerVolumeRspamd=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_rspamd-vol-1)
writeLog 'info' "Using RSPAMD volume: ${dockerVolumeRspamd}"
# exit if mail or crypt containers cannot be found (mailcow not initialized beforehand)
if [ -z "$dockerVolumeMail" ] || [ -z "$dockerVolumeCrypt" ]; then
    writeLog 'error' '5' "Cannot find mail volume. Mailcow probably not initialized before running restore."
    exitError 5
fi

### restore SQL
if [ "$restoreSQL" -eq 1 ]; then
    writeLog 'task' "Restoring mailcow database"

    # sql restore pre-requisites
    sqlBackup=$(find "${backupLocation}/tmp" -iname "*.sql")
    if [ -n "$sqlBackup" ]; then
        # start mysql container if not already running
        if ! docker container inspect -f '{{ .State.Running }}' ${COMPOSE_PROJECT_NAME}_mysql-mailcow_1 > /dev/null 2>&1; then
            docker-compose up -d mysql-mailcow > /dev/null 2>&1
            if docker container inspect -f '{{ .State.Running }}' ${COMPOSE_PROJECT_NAME}_mysql-mailcow_1 > /dev/null 2>&1; then
                sqlRunning=1
            else
                writeLog 'done' 'error'
                writeLog 'error' '12' "Cannot start mysql-mailcow container -- cannot restore mailcow database!"
                errorCount=$((errorCount+1))
            fi
        else
            sqlRunning=1
        fi
    else
        writeLog 'done' 'error'
        writeLog 'error' '11' "Cannot locate SQL backup -- cannot restore mailcow database!"
        errorCount=$((errorCount+1))
    fi

    # restore sql
    if [ "$sqlRunning" -eq 1 ]; then
        if docker exec -i "$(docker-compose ps -q mysql-mailcow)" mysql -u${DBUSER} -p${DBPASS} ${DBNAME} < "${sqlBackup}" > /dev/null 2>&1; then
            writeLog 'done'
        else
            writeLog 'done' 'error'
            writeLog 'error' '13' "Something went wrong while trying to restore SQL database. Perhaps try again?"
            errorCount=$((errorCount+1))
        fi
    fi
fi

### stop containers (necessary for all restore operations except SQL)
writeLog 'task' "Stopping mailcow"
if ! docker-compose down --timeout "${dockerStopTimeout}" > /dev/null 2>&1; then
    writeLog 'done' 'error'
    writeLog 'error' '20' "Unable to bring mailcow containers down -- cannot reliably restore. Aborting."
    exitError 20
fi
if [ "$( docker ps --filter "name=${COMPOSE_PROJECT_NAME}" -q | wc -l )" -gt 0 ]; then
    writeLog 'done' 'error'
    writeLog 'error' '20' "Unable to bring mailcow containers down -- cannot reliably restore. Aborting."
    exitError 20
fi
writeLog 'done'

### restore mail and encryption key
if [ "$restoreMail" -eq 1 ]; then
    if [ "$verbose" -eq 1 ]; then
        writeLog 'info' "Restoring email"
    else
        writeLog 'task' "Restoring email"
    fi

    # restore email messages
    doRestore "${COMPOSE_PROJECT_NAME}_vmail-vol-1" "$dockerVolumeMail"; ec="$?"
    case "$ec" in
        0)
            if [ "$verbose" -eq 1 ]; then
                writeLog 'success' "Email messages restored"
            else
                writeLog 'done'
            fi
            ;;
        1)
            if [ "$verbose" -eq 1 ]; then
                writeLog 'error' '52' "There was an error restoring one or more email messages."
            else
                writeLog 'done' 'error'
                writeLog 'error' '52' "There was an error restoring one or more email messages."
            fi
            ;;
        2)
            if [ "$verbose" -eq 1 ]; then
                writeLog 'error' '51' "Cannot locate email message backups!"
            else
                writeLog 'done' 'error'
                writeLog 'error' '51' "Cannot locate email message backups!"
            fi
            ;;
    esac

    # restore encryption key
    doRestore "${COMPOSE_PROJECT_NAME}_crypt-vol-1" "$dockerVolumeCrypt"; ec="$?"
    case "$ec" in
        0)
            if [ "$verbose" -eq 1 ]; then
                writeLog 'success' "Encryption key restored"
            else
                writeLog 'done'
            fi
            ;;
        1)
            if [ "$verbose" -eq 1 ]; then
                writeLog 'error' '52' "There was an error restoring the encryption key! Any restored messages are likely *not* readable!"
            else
                writeLog 'done' 'error'
                writeLog 'error' '52' "There was an error restoring the encryption key! Any restored messages are likely *not* readable!"
            fi
            ;;
        2)
            if [ "$verbose" -eq 1 ]; then
                writeLog 'error' '51' "Cannot locate encryption key backup!"
            else
                writeLog 'done' 'error'
                writeLog 'error' '51' "Cannot locate encryption key backup!"
            fi
            ;;
    esac
fi

### restore postfix
if [ "$restorePostfix" -eq 1 ]; then
    if [ "$verbose" -eq 1 ]; then
        writeLog 'info' "Restoring postfix files"
    else
        writeLog 'task' "Restoring postfix files"
    fi

    doRestore "${COMPOSE_PROJECT_NAME}_postfix-vol-1" "$dockerVolumePostfix"; ec="$?"
    case "$ec" in
        0)
            if [ "$verbose" -eq 1 ]; then
                writeLog 'success' "Postfix files restored"
            else
                writeLog 'done'
            fi
            ;;
        1)
            if [ "$verbose" -eq 1 ]; then
                writeLog 'error' '52' "There was an error restoring one or more postfix files."
            else
                writeLog 'done' 'error'
                writeLog 'error' '52' "There was an error restoring one or more postfix files."
            fi
            ;;
        2)
            if [ "$verbose" -eq 1 ]; then
                writeLog 'error' '51' "Cannot locate postfix backups!"
            else
                writeLog 'done' 'error'
                writeLog 'error' '51' "Cannot locate postfix backups!"
            fi
            ;;
    esac
fi

### restore rspamd
if [ "$restoreRspamd" -eq 1 ]; then
    if [ "$verbose" -eq 1 ]; then
        writeLog 'info' "Restoring Rspamd files"
    else
        writeLog 'task' "Restoring Rspamd files"
    fi

    doRestore "${COMPOSE_PROJECT_NAME}_rspamd-vol-1" "$dockerVolumeRspamd"; ec="$?"
    case "$ec" in
        0)
            if [ "$verbose" -eq 1 ]; then
                writeLog 'success' "Rspamd files restored"
            else
                writeLog 'done'
            fi
            ;;
        1)
            if [ "$verbose" -eq 1 ]; then
                writeLog 'error' '52' "There was an error restoring one or more Rspamd files."
            else
                writeLog 'done' 'error'
                writeLog 'error' '52' "There was an error restoring one or more Rspamd files."
            fi
            ;;
        2)
            if [ "$verbose" -eq 1 ]; then
                writeLog 'error' '51' "Cannot locate Rspamd backups!"
            else
                writeLog 'done' 'error'
                writeLog 'error' '51' "Cannot locate Rspamd backups!"
            fi
            ;;
    esac
fi

### restore redis
if [ "$restoreRedis" -eq 1 ]; then
    if [ "$verbose" -eq 1 ]; then
        writeLog 'info' "Restoring redis database"
    else
        writeLog 'task' "Restoring redis database"
    fi

    doRestore "${COMPOSE_PROJECT_NAME}_redis-vol-1" "$dockerVolumeRedis"; ec="$?"
    case "$ec" in
        0)
            if [ "$verbose" -eq 1 ]; then
                writeLog 'success' "Redis database restored"
            else
                writeLog 'done'
            fi
            ;;
        1)
            if [ "$verbose" -eq 1 ]; then
                writeLog 'error' '52' "There was an error restoring the redis database. This is usually *not* a serious issue."
            else
                writeLog 'done' 'error'
                writeLog 'error' '52' "There was an error restoring the redis database. This is usually *not* a serious issue."
            fi
            ;;
        2)
            if [ "$verbose" -eq 1 ]; then
                writeLog 'error' '51' "Cannot locate redis database backups!"
            else
                writeLog 'done' 'error'
                writeLog 'error' '51' "Cannot locate redis database backups!"
            fi
            ;;
    esac
fi

### restart mailcow
writeLog 'task' "Starting mailcow"
if ! docker-compose up -d > /dev/null 2>&1; then
    writeLog 'done' 'warn'
    writeLog 'warn' '21' "Unable to automatically start mailcow containers. Please attempt a manual start and note any errors."
    warnCount=$((warnCount+1))
fi
writeLog 'done'

### exit gracefully
if [ "$errorCount" -gt 0 ]; then
    # note non-terminating errors
    printf "%s[%s] --- %s execution completed with %s error(s) ---\n%s" "$err" "$(stamp)" "$scriptName" "$errorCount" "$norm" >> "$logfile"
    exit 98
elif [ "$warnCount" -gt 0 ]; then
    printf "%s[%s] --- %s execution completed with %s warning(s) ---\n%s" "$yellow" "$(stamp)" "$scriptName" "$warnCount" "$norm" >> "$logfile"
    exit 97
else
    writeLog 'success' "All processes completed"
    printf "%s[%s] --- %s execution completed ---\n%s" "$magenta" "$(stamp)" "$scriptName" "$norm" >> "$logfile"
    exit 0
fi

### error codes:
# 1: parameter error
# 2: not run as root
# 3: docker not installed
# 4: cannot change to mailcow directory
# 5: mailcow not initialized before running script
# 1x: SQL errors
#     11: cannot locate SQL dump in backup directory
#     12: cannot start mysql-mailcow container
#     13: restoring SQL dump was unsuccessful
# 2x: Docker/Docker-Compose errors
#     20: cannot bring docker container(s) down successfully
#     21: cannot bring docker container(s) up successfully
# 5x: File restore errors
#     51: cannot locate source files in backup directory
#     52: error restoring one or more files
# 97: script completed with 1 or more warnings
# 98: script completed with 1 or more non-terminating errors
# 99: TERM signal trapped

#EOF
