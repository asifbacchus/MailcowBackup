#!/bin/sh

#######
### restore mailcow from borgbackup repository
### this assumes three things:
###     1. standard mailcow-dockerized setup as per the docs
###     2. backups made using the backup script from this git repo
###     3. backups successfully written to your borg repo
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

badDetails() {
    if [ "$1" = 'empty' ]; then
        writeLog 'done' 'error'
        writeLog 'error' '10' "details:${2} cannot be blank/empty."
        exitError 130
    elif [ "$1" = 'dne' ]; then
        writeLog 'done' 'error'
        writeLog 'error' '11' "details:${2} file or directory does not exist."
        exitError 131
    fi
}

consoleError() {
    printf "\n%s%s\n" "$err" "$2"
    printf "Exiting.\n\n%s" "$norm"
    exit "$1"
}

exitError() {
    printf "%s[%s] --- %s execution completed with error ---\n%s" "$err" "$(stamp)" "$scriptName" "$norm" >>"$logfile"
    exit "$1"
}

scriptHelp() {
    textNewline
    printf "%sUsage: %s [parameters]%s\n\n" "$bold" "$scriptName" "$norm"
    textNewline
    textblock "If a parameter is not supplied, its default value will be used. Switch parameters will remain DEactivated if NOT specified."
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
    printf "\n%s%s***%s***%s\n" "$bold" "$magenta" "$1" "$norm"
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
    printf "%s[%s] -- [ERROR] 99: Caught signal --%s\n" "$err" "$(stamp)" "$norm" >>"$logfile"
    cleanup
    printf "%s[%s] --- %s execution terminated via signal ---\n%s" "$err" "$(stamp)" "$scriptName" "$norm" >>"$logfile"
    exit 99
}

writeLog() {
    if [ "$1" = "task" ]; then
        printf "%s[%s] -- [INFO] %s... " "$info" "$(stamp)" "$2" >>"$logfile"
    elif [ "$1" = "done" ]; then
        if [ -z "$2" ]; then
            printf "%sdone%s --\n%s" "$ok" "$info" "$norm" >>"$logfile"
        elif [ "$2" = "error" ]; then
            printf "%sERROR%s --\n%s" "$err" "$info" "$norm" >>"$logfile"
        elif [ "$2" = "warn" ]; then
            printf "%swarning%s --\n%s" "$yellow" "$info" "$norm" >>"$logfile"
        fi
    elif [ "$1" = "error" ]; then
        printf "%s[%s] -- [ERROR] %s: %s --\n%s" "$err" "$(stamp)" "$2" "$3" "$norm" >>"$logfile"
    elif [ "$1" = "warn" ]; then
        printf "%s[%s] -- [WARNING] %s --\n%s" "$yellow" "$(stamp)" "$2" "$norm" >>"$logfile"
    elif [ "$1" = "info" ]; then
        printf "%s[%s] -- [INFO] %s --\n%s" "$info" "$(stamp)" "$2" "$norm" >>"$logfile"
    elif [ "$1" = "success" ]; then
        printf "%s[%s] -- [SUCCESS] %s --\n%s" "$ok" "$(stamp)" "$2" "$norm" >>"$logfile"
    fi
}

### parameter defaults
# script related
scriptPath="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
scriptName="$(basename "$0")"
configDetails="$scriptPath/${scriptName%.*}.details"
errorCount=0
warnCount=0
backupLocation=""
restoreMail=1
restoreSQL=1
restorePostfix=1
restoreRedis=1
restoreRspamd=1
# logfile default: same location and name as script but with '.log' extension
logfile="$scriptPath/${scriptName%.*}.log"
# mailcow/docker related
mcConfig='/opt/mailcow-dockerized/mailcow.conf'
mcDockerCompose='/opt/mailcow-dockerized/docker-compose.yml'
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
        # set verbose logging from borg
        borgParams='--list'
        ;;
    -c|--config|--details)
        # location of configuration details file
        if [ -n "$2" ]; then
            if [ -f "$2" ]; then
                configDetails=${2%/}
                shift
            else
                consoleError '1' "$1: configuration file ($2) does not exist."
            fi
        else
            consoleError '1' "$1: cannot be blank/empty."
        fi
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
                backupLocation="$2"
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
        printf "\n%Unknown option: %s\n" "$err" "$1"
        printf "Use '--help' for valid options.%s\n\n" "$norm"
        exit 1
        ;;
    esac
    shift
done

### pre-flight checks
# set path so checks are valid for this script environment
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# docker installed?
if ! command -v docker >/dev/null; then
    consoleError '3' 'docker does not seem to be installed!'
fi
# borg installed?
if ! command -v borg >/dev/null; then
    consoleError '3' 'borgbackup does not seem to be installed!'
fi
# details file?
if [ ! -f "$configDetails" ]; then
    consoleError '1' "configuration file ($configDetails) cannot be found."
fi
# mailcow.conf?
if [ ! -f "$mcConfig" ]; then
    consoleError '1' "mailcow configuration file ($mcConfig) cannot be found."
fi
# docker-compose configuration?
if [ ! -f "$mcDockerCompose" ]; then
    consoleError '1' "docker-compose configuration ($mcDockerCompose) cannot be found."
fi

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
if ! printf "%s[%s] --- Start %s execution ---\n%s" "$magenta" "$(stamp)" "$scriptName" "$norm" 2>/dev/null >>"$logfile"; then
    consoleError '1' "Unable to write to log file ($logfile)"
fi
writeLog 'info' "Log located at $logfile"

### get location of docker volumes
dockerVolumeMail=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_vmail-vol-1)
printf "%s[%s] -- [INFO] Using MAIL volume: %s --%s\n" \
    "$cyan" "$(stamp)" "$dockerVolumeMail" "$norm" >>"$logfile"
dockerVolumeRspamd=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_rspamd-vol-1)
printf "%s[%s] -- [INFO] Using RSPAMD volume: %s --%s\n" \
    "$cyan" "$(stamp)" "$dockerVolumeRspamd" "$norm" >>"$logfile"
dockerVolumePostfix=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_postfix-vol-1)
printf "%s[%s] -- [INFO] Using POSTFIX volume: %s --%s\n" \
    "$cyan" "$(stamp)" "$dockerVolumePostfix" "$norm" >>"$logfile"
dockerVolumeRedis=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_redis-vol-1)
printf "%s[%s] -- [INFO] Using REDIS volume: %s --%s\n" \
    "$cyan" "$(stamp)" "$dockerVolumeRedis" "$norm" >>"$logfile"
dockerVolumeCrypt=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_crypt-vol-1)
printf "%s[%s] -- [INFO] Using MAILCRYPT volume: %s --%s\n" \
    "$cyan" "$(stamp)" "$dockerVolumeCrypt" "$norm" >>"$logfile"

### source configuration details file
case "${configDetails}" in
/*)
    # absolute path, no need to rewrite variable
    # shellcheck source=./backup.details
    . "${configDetails}"
    ;;
*)
    # relative path, prepend './' to create absolute path
    # shellcheck source=./backup.details
    . "./${configDetails}"
    ;;
esac
writeLog 'info' "Configuration file: ${yellow}${configDetails}${info} imported"

### verify borg variables
# verify borg base directory
writeLog 'task' 'Verify details:borgBaseDir'
if [ -z "${borgBaseDir}" ]; then
    badDetails empty 'borgBaseDir'
elif [ ! -d "${borgBaseDir}" ]; then
    badDetails dne 'borgBaseDir'
fi
export BORG_BASE_DIR="${borgBaseDir%/}"
writeLog 'done'
# check path to SSH keyfile
writeLog 'task' 'Verify details:borgSSHKey'
if [ -z "${borgSSHKey}" ]; then
    badDetails empty 'borgSSHKey'
elif [ ! -f "${borgSSHKey}" ]; then
    badDetails dne 'borgSSHKey'
fi
export BORG_RSH="ssh -i ${borgSSHKey}"
writeLog 'done'
# check borg repo connect string
writeLog 'task' 'Verify details:borgConnectRepo'
if [ -z "${borgConnectRepo}" ]; then
    badDetails empty 'borgConnectRepo'
fi
export BORG_REPO="${borgConnectRepo}"
writeLog 'done'
# check borg repo password
writeLog 'task' 'Verify details:borgRepoPassphrase'
if [ -z "${borgRepoPassphrase}" ]; then
    # an empty repo passphrase is considered a mistake so throw an error
    # if the user meant to enter an empty passphrase they should use 'NONE'
    badDetails empty 'borgRepoPassphrase'
elif [ "${borgRepoPassphrase}" = 'NONE' ]; then
    # password intentionally blank, use but issue warning
    export BORG_PASSPHRASE=''
    writeLog 'done' 'warn'
    writeLog 'warn' 'Using a borg repo with a blank password is an insecure configuration!'
    warnCount=$((warnCount + 1))
else
    export BORG_PASSPHRASE="${borgRepoPassphrase}"
    writeLog 'done'
fi
# check borg repo keyfile location
writeLog 'task' 'Verify details:borgKeyfileLocation'
if [ -z "${borgKeyfileLocation}" ]; then
    # will use default location
    writeLog 'done'
else
    # verify keyfile location exists
    if [ ! -f "${borgKeyfileLocation}" ]; then
        badDetails dne 'bogKeyfileLocation'
    fi
    export BORG_KEY_FILE="${borgKeyfileLocation}"
    writeLog 'done'
fi
# export borg remote path, if specified
if [ -n "${borgRemote}" ]; then export BORG_REMOTE_PATH="${borgRemote}"; fi

### create borg temp dir
## python requires a writable temporary directory when unpacking borg and
## executing commands. This defaults to /tmp but many systems mount /tmp with
## the 'noexec' option for security. Thus, we will use/create a 'tmp' folder
## within the BORG_BASE_DIR and instruct python to use that instead of /tmp

# check if BORG_BASE_DIR/tmp exists, if not, create it
if [ ! -d "${borgBaseDir}/tmp" ]; then
    if ! mkdir "${borgBaseDir}/tmp" 2>/dev/null; then
        writeLog 'error' '31' "Unable to create borg temp directory (${borgBaseDir}/tmp)"
        exitError 31
    fi
fi
export TMPDIR="${borgBaseDir}/tmp"

### change to mailcow directory so docker commands run properly
cd "$(dirname ${mcConfig})" || writeLog 'error' '100' "Could not change to mailcow directory." && exitError 100

#TODO: stop containers
#TODO: pull backup via borg
#TODO: copy backups to correct docker volumes
#TODO: copy additional files to correct locations
#TODO: restart docker containers
#TODO: optionally reindex dovecot (parameter)
#TODO: delete downloaded backup (parameter)

### exit gracefully
writeLog 'success' "All processes completed"
printf "%s[%s] --- %s execution completed ---\n%s" "$magenta" "$(stamp)" "$scriptName" "$norm" >>"$logfile"
# note non-terminating errors
if [ "$errorCount" -gt 0 ]; then
    printf "%s%s errors encountered!%s\n" "$err" "$errorCount" "$norm" >>"$logfile"
fi
# note warnings
if [ "$warnCount" -gt 0 ]; then
    printf "%s%s warnings issued!%s\n" "$yellow" "$warnCount" "$norm" >>"$logfile"
fi
exit 0

### error codes:
# 1: parameter error
# 2: not run as root
# 3: borg or docker not installed
# 10: null configuration variable in details file
# 11: invalid configuration variable in details file
# 99: TERM signal trapped
# 100: could not change to mailcow-dockerized directory
# 101: could not stop container(s)
# 102: could not start container(s)
# 110: borg exited with a critical error

#EOF
