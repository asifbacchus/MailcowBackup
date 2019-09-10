#!/bin/bash


### Text formatting presets
normal="\e[0m"
bold="\e[1m"
default="\e[39m"
err="\e[1;31m"
warn="\e[1;93m"
ok="\e[32m"
lit="\e[93m"
op="\e[39m"
info="\e[96m"
note="\e[95m"


### Functions ###

### scriptHelp -- display usage information for this script
function scriptHelp {
    echo -e "${bold}${note}\n${scriptName} usage instructions:\n${normal}"
    echo -e "${default}This script performs a backup of your Mailcow system"
    echo -e "assuming a fairly standard set up such as outlined at"
    echo -e "${lit}https://mytechiethoughts.com${default}.  Full details about"
    echo -e "this script can be found at that site."
    echo -e "${bold}\nThe script performs the following tasks:${normal}${default}"
    echo -e "1. Stops mailflow (postfix & dovecot) containers."
    echo -e "2. Optionally copies a 503 error page to your webroot."
    echo -e "3. Dumps Mailcow's SQL DB to a temporary directory."
    echo -e "4. Invokes borgbackup to backup your SQL info, Mailcow settings"
    echo -e "\tand (raw) data files along with any other files you specify."
    echo -e "5. Removes temp files, the 503 error page and restores"
    echo -e "\tMailcow to operational status."
    echo -e "\nThe readme file included in this script's git contains detailed"
    echo -e "usage information. The following is a brief summary:\n"
    echo -e "${bold}***This script scans for your mailcow configuration file"
    echo -e "either with the default name or with your provided filename. If"
    echo -e "multiple files with this name are on your system, the script"
    echo -e "WILL get confused and exit with errors***${normal}${default}"
    echo -e "${bold}${note}\nOptional parameters:${normal}${default}"
    echo -e "${lit}\n-1, Timeout for containers to STOP before error${default}"
    echo -e "The number of seconds to wait for a docker container to STOP"
    echo -e "before aborting the procedure and exiting this script with an"
    echo -e "error."
    echo -e "${info}Default: 120 seconds${default}"
    echo -e "${lit}\n-2, Timeout for containers to START before error${default}"
    echo -e "The number of seconds to wait for a docker container to START"
    echo -e "before aborting the procedure and exiting this script with an"
    echo -e "error."
    echo -e "${info}Default: 180 seconds${default}"
    echo -e "${lit}\n-5, Location of 503 error page file${default}"
    echo -e "FULL PATH to the 503 error page HTML file you want copied to your"
    echo -e "webroot to inform users the server is down during the backup. If"
    echo -e "you don't specify a path/file, the default will be used. If the"
    echo -e "default cannot be found, a warning will be logged and the script"
    echo -e "will continue."
    echo -e "${info}Default: ScriptPath/503.html${default}"
    echo -e "${lit}\n-b, Location of file with borg repo details${default}"
    echo -e "FULL PATH to the plain text file containing all information needed"
    echo -e "to connect and process your borg repo. Details on the structure of"
    echo -e "this file are in the readme and on ${lit}https://mytechiethoughts.com${default}"
    echo -e "${info}Default: ScriptPath/nc_borg.details${default}"
    echo -e "${lit}\n-d, File name of the docker-compose configuration file${default}"
    echo -e "Name of the docker-compose configuration file that Mailcow uses"
    echo -e "to build/start/stop all containers.  This will only be searched"
    echo -e "for in the path found to contain your mailcow configuration file."
    echo -e "${info}Default: docker-compose.yml${default}"
    echo -e "${lit}\n-l, Location to save log file${default}"
    echo -e "This script writes a detailed log file of all activities.  It is"
    echo -e "structured in an way easy for log parsers (like Logwatch) to read."
    echo -e "${info}Default: ScriptPath/ScriptName.log${default}"
    echo -e "${lit}\n-m, File name of the Mailcow build configuration file${default}"
    echo -e "Name of the Mailcow master build configuration file that has all"
    echo -e "variables and configuration info unique to your Mailcow setup."
    echo -e "This script will search for any file matching what you specify"
    echo -e "so please ensure you don't have multiple files laying around with"
    echo -e "the same name! The path where this file is found is used for all"
    echo -e "docker-based operations in this script."
    echo -e "${info}Default: mailcow.conf${default}"
    echo -e "${lit}\n-v, Verbose output from borgbackup${default}"
    echo -e "By default, this script will only log summary data from borg."
    echo -e "If you need/want more detailed information, the verbose setting"
    echo -e "will list every file processed along with their status. Note: Your"
    echo -e "log file can quickly get very very large using this option!"
    echo -e "${info}Default: NOT activated (standard logging)${default}"
    echo -e "${lit}\n-w, webserver's webroot directory${default}"
    echo -e "This is the location from which your webserver (NGINX, Apache,"
    echo -e "etc.) physically stores files to be served.  This is NOT the"
    echo -e "configuration directory for your webserver!  It is the place"
    echo -e "where the actual HTML/PHP/CSS/JS/etc. files are stored."
    echo -e "NOTE: If you omit this option, then the entire 503 copy process"
    echo -e "will be skipped regardless of the presence of a 503.html file."
    echo -e "If you don't want to use the 503 feature, omitting this is an easy"
    echo -e "way to skip it!"
    echo -e "${info}Default: NONE${default}"
    echo -e "${lit}\n-?, This help screen${default}\n"
    echo -e "${bold}Please refer to the readme file and/or ${lit}https://mytechiethoughts.com${default}"
    echo -e "for more information on this script.${normal}\n"
    # exit with code 1 -- there is no use logging this
    exit 1
}

### Generate dynamic timestamp
function stamp {
    echo `date +%F" "%T`
}

### quit -- exit the script after logging any errors, warnings, etc.
function quit {
    # list generated warnings, if any
    if [ ${#exitWarn[@]} -gt 0 ]; then
        echo -e "\n${warn}${scriptName} generated the following warnings:" \
            "${normal}" >> "$logFile"
        for warnCode in "${exitWarn[@]}"; do
            warnStamp="${warnCode%%_*}"
            warnValue="${warnCode##*_}"
            echo -e "${warn}${warnStamp} -- [WARNING]" \
                "${warningExplain[$warnValue]} (code: ${warnValue}) --" \
                "${normal}" >> "$logFile"
        done
    fi
    if [ -z "${exitError}" ]; then
        # exit cleanly
        echo -e "${note}[$(stamp)] -- ${scriptName} completed" \
            "--${normal}" >> "$logFile"
        exit 0
    else
        # list generated errors and explanations then exit script with code 2
        echo -e "\n${err}${scriptName} generated the following errors:" \
            "${normal}" >> "$logFile"
        for errCode in "${exitError[@]}"; do
            errStamp="${errCode%%_*}"
            errValue="${errCode##*_}"
            echo -e "${err}${errStamp} -- [ERROR] ${errorExplain[$errValue]}" \
                "(code: ${errValue}) --${normal}" >> "$logFile"
        done
        exit 2
    fi
}

function checkExist {
    if [ "$1" = "ff" ]; then
        # find file
        if [ -f "$2" ]; then
            # found
            return 0
        else
            # not found
            return 1
        fi
    elif [ "$1" = "fs" ]; then
        # find file > 0 bytes
        if [ -s "$2" ]; then
            # found
            return 0
        else
            # not found
            return 1
        fi
    elif [ "$1" = "fd" ]; then
        # find directory
        if [ -d "$2" ]; then
            # found
            return 0
        else
            # not found
            return 1
        fi
    fi
}

### cleanup - cleanup files and directories created by this script
function cleanup {
    ## remove SQL dump file and directory
    rm -rf "$sqlDumpDir" >> "$logFile" 2>&1
    # verify directory is gone
    checkExist fd "$sqlDumpDir"
    checkResult="$?"
    if [ "$checkResult" = "0" ]; then
        # directory still exists
        exitWarn+=("[$(stamp)]_111")
    else
        # directory removed
        echo -e "${op}[$(stamp)] Removed SQL temp directory${normal}" \
            >> "$logFile"
    fi

    ## remove 503 error page
    # check value of 'clean503' to see if this is necessary (=1) otherwise, skip
    if [ "$clean503" = "1" ]; then
        # proceed with cleanup
        echo -e "${op}[$(stamp)] Removing 503 error page..." >> "$logFile"
        rm -f "$webroot/$err503File" >> "$logFile" 2>&1
        # verify file is actually gone
        checkExist ff "$webroot/$err503File"
        checkResult="$?"
        if [ "$checkResult" = "0" ]; then
            # file still exists
            exitWarn+=("[$(stamp)]_5030")
        else
            # file removed
            echo -e "${info}[$(stamp)] -- [INFO] 503 page removed from webroot" \
                "--${normal}" >> "$logFile"
        fi
    else
        echo -e "${op}[$(stamp)] 503 error page never copied to webroot," \
            "nothing to cleanup" >> "$logFile"
    fi

    ## restart mailflow docker containers
    # start and verify postfix
    operateDocker start postfix
    if [ "$dockerResultState" = "true" ]; then
        echo -e "${info}[$(stamp)] -- [INFO] Postfix container is running --" \
            "${normal}" >> "$logFile"
    else
        exitError+=("[$(stamp)]_103")
    fi
    # start and verify dovecot
    operateDocker start dovecot
    if [ "$dockerResultState" = "true" ]; then
        echo -e "${info}[$(stamp)] -- [INFO] Dovecot container is running --" \
            "${normal}" >> "$logFile"
    else
        exitError+=("[$(stamp)]_104")
    fi
}

### operate docker containers
function operateDocker {
# determine action to take
if [ "$1" = "stop" ]; then
    containerName="$(docker ps --format '{{.Names}}' --filter name=${COMPOSE_PROJECT_NAME}_${2}-mailcow_1)"

    echo -e "${op}[$(stamp)] Stopping ${2}-mailcow container...${normal}" \
        >> "$logFile"
    docker-compose stop --timeout ${dockerStopTimeout} ${2}-mailcow \
        2>> "$logFile"
    # verify container stopped (should return true)
    dockerResultState=$(docker inspect -f '{{ .State.Running }}' \
        $containerName)
    # verify clean stop (exit code 0)
    dockerResultExit=$(docker inspect -f '{{ .State.ExitCode }}' \
        $containerName)
elif [ "$1" = "start" ]; then
    echo -e "${op}[$(stamp)] Starting ${2}-mailcow container...${normal}" \
        >> "$logFile"
    docker-compose start ${2}-mailcow 2>> "$logFile"
    # verify
    containerName="$(docker ps --format '{{.Names}}' --filter name=${COMPOSE_PROJECT_NAME}_${2}-mailcow_1)"
    dockerResultState=$(docker inspect -f '{{ .State.Running }}' \
        $containerName)
fi
}

### End of Functions ###


### Default parameters

# store the logfile in the same directory as this script using the script's name
# with the extension .log
scriptPath="$( cd "$( dicontainerName "${BASH_SOURCE[0]}" )" && pwd )"
scriptName="$( basename ${0} )"
logFile="$scriptPath/${scriptName%.*}.log"

# Set default mailcow configuration filename
mailcowConfigFile=mailcow.conf

# Set default docker-compose filename
dockerComposeFile=docker-compose.yml

# set default 503 error page name and location in scriptPath
err503Path="$scriptPath/503.html"
err503File="${err503Path##*/}"

# Set default docker-compose stop timeout
dockerStopTimeout=120

# Set default docker-compose start timeout
dockerStartTimeout=180

# set default borgDetails path to scriptPath
borgDetails="$scriptPath/mc_borg.details"

# set borg parameters to 'normal' verbosity
borgCreateParams='--stats'
borgPruneParams='--list'


### Set script parameters to null and initialize array variables
unset mailcowConfigFilePath
unset mailcowPath
unset dockerComposeFilePath
unset PARAMS
unset sqlDumpDir
unset webroot
unset clean503
unset borgXtra
unset borgExclude
unset borgPrune
unset BORG_BASE_DIR
unset BORG_RSH
unset BORG_REPO
unset BORG_PASSPHRASE
unset BORG_REMOTE_PATH
unset TMPDIR
unset dockerVolumeMail
unset dockerVolumeRspamd
unset dockerVolumePostfix
unset dockerVolumeRedis
unset dockerVolumeCrypt
exitError=()
errorExplain=()
exitWarn=()
warningExplain=()
borgConfig=()
xtraFiles=()

### Error codes
errorExplain[101]="Could not stop Postfix container. Please check docker logs"
errorExplain[102]="Could not stop Dovecot container. Please check docker logs"
errorExplain[103]="Could not start Postfix container. Please check docker logs"
errorExplain[104]="Could not start Dovecot container. Please check docker logs"
errorExplain[201]="There was a problem dumping the SQL database. It has NOT been backed up"
errorExplain[202]="There was a problem saving redis state information. It has NOT been backed up"
errorExplain[210]="Invalid or non-existant borg base directory specified (borg backup details file)"
errorExplain[211]="Invalid or non-existant path to borg SSH keyfile (borg backup details file)"
errorExplain[212]="Name of borg repo was not specified (borg backup details file)"
errorExplain[215]="Could not find/create 'tmp' directory within borg base directory. Please manually create it and ensure it's writable"
errorExplain[220]="Borg exited with a critical error. Please check this script's logfile for details"
errorExplain[221]="Borg prune exited with ERRORS. Please check this script's logfile for details"


### Warning codes & messages
warningExplain[111]="Could not remove SQL dump file and directory, please remove manually"
warningExplain[5030]="Could not remove 503 error page. This MUST be removed manually before NGINX will serve webclients!"
warningExplain[5031]="No webroot path was specified (-w parameter missing)"
warningExplain[5032]="The specified webroot (-w parameter) could not be found"
warningExplain[5033]="No 503 error page could be found. If not using the default located in the script directory, then check your -5 parameter"
warningExplain[5035]="Error copying 503 error page to webroot"
warn503="Web users will NOT be informed the server is down!"
warningExplain[2111]="No password used for SSH keys or access to remote borg repo. This is an insecure configuration"
warningExplain[2112]="No remote borg instance specified. Operations will be slower in this configuration"
warningExplain[2113]="The specified file containing extra files for inclusion in borgbackup could not be found"
warningExplain[2114]="The specified file containing exclusion patterns for borgbackup could not be found. Backup was performed as though NO exclusions were defined"
warningExplain[2115]="No paramters provided for borg prune. No repo pruning has taken place. You should reconsider this decision to control the size/history of your backups"
warningExplain[2116]="No additional locations are specified for inclusion in backup. ONLY Mailcow data and config files will be backed up (NO system files, etc). If this is unintentional, check the inclusion file referenced in your borgbackup settings"
warningExplain[2200]="Borg completed with warnings. Please check this script's logfile for details"
warningExplain[2201]="Borg exited with an unknown return-code. Please check this script's logfile for details"
warningExplain[2210]="Borg prune exited with warnings. Please check this script's logfile for details"
warningExplain[2212]="Borg prune exited with an unknown return-code. Please check this script's logfile for details"


### Process script parameters

# If parameters are provided but don't start with '-' then show the help page
# and exit with an error
if [ -n "$1" ] && [[ ! "$1" =~ ^- ]]; then
    # show script help page
    scriptHelp
fi

# use GetOpts to process parameters
while getopts ':l:v5:w:b:m:d:1:2:' PARAMS; do
    case "$PARAMS" in
        l)
            # use provided location for logFile
            logFile="${OPTARG%/}"
            ;;
        v)
            # verbose output from Borg
            borgCreateParams='--list --stats'
            borgPruneParams='--list'
            ;;
        5)
            # Full path to 503 error page
            err503Path="${OPTARG%/}"
            err503File="${err503Path##*/}"
            ;;
        w)
            # path to webserver webroot to copy 503 error page
            webroot="${OPTARG%/}"
            ;;
        b)
            # path to file containing borgbackup settings and details
            borgDetails="${OPTARG%/}"
            ;;
        m)
            # name of mailcow configuration file
            mailcowConfigFile="${OPTARG}"
            ;;
        d)
            # name of docker-compose configuration file
            dockerComposeFile="${OPTARG}"
            ;;
        1)
            # docker-compose stop timeout in seconds
            dockerStopTimeout="${OPTARG}"
            ;;
        2)
            # docker-compose start timeout in seconds
            dockerStartTimeout="${OPTARG}"
            ;;
        ?)
            # unrecognized parameters trigger scriptHelp
            scriptHelp
            ;;
    esac
done


### Verify script pre-requisties

## If not running as root, display error on console and exit
if [ $(id -u) -ne 0 ]; then
    echo -e "\n${err}This script MUST be run as ROOT. Exiting.${normal}"
    exit 3
fi

## Find mailcow configuration file so additional variables can be read
mailcowConfigFilePath=$( find / -mount -name "$mailcowConfigFile" -print )
if [ -z "$mailcowConfigFilePath" ]; then
    echo -e "\n${err}Could not locate the specified mailcow configuration" \
        "file: ${lit}${mailcowConfigFile}${normal}"
    exit 1
fi

## Find docker-compose file using mailcow configuration file path as a reference
mailcowPath="${mailcowConfigFilePath%/$mailcowConfigFile*}"
dockerComposeFilePath="$mailcowPath/$dockerComposeFile"
checkExist ff "$dockerComposeFilePath"
checkResult="$?"
if [ "$checkResult" = 1 ]; then
    echo -e "\n${err}Could not locate docker-compose configuration file:" \
        "${lit}${dockerComposeFilePath}${normal}"
    exit 1
fi

## Ensure borgDetails file exists
checkExist ff "$borgDetails"
checkResult="$?"
if [ "$checkResult" = "1" ]; then
    # sqlDetails file cannot be found
    echo -e "\n${err}The file containing your borgbackup details does not" \
        "exist (-b parameter)${normal}\n"
    exit 1
fi


### Log start of script operations
echo -e "${note}[$(stamp)] --- Start $scriptName execution ---${normal}" \
    >> "$logFile"
echo -e "${info}[$(stamp)] -- [INFO] using ${lit}${mailcowConfigFilePath}" \
    >> "$logFile"
echo -e "${info}[$(stamp)] -- [INFO] using ${lit}${dockerComposeFilePath}" \
    >> "$logFile"

### Import additional variables from mailcow configuration file
source "${mailcowConfigFilePath}"

### Export PATH so this script can access all docker and docker-compose commands
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

### Export logFile variable for use by Borg
export logFile="$logFile"

### Export docker container startup timeout variable
export COMPOSE_HTTP_TIMEOUT=${dockerStartTimeout}

## Get docker volume paths on filesystem
dockerVolumeMail=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_vmail-vol-1)
dockerVolumeRspamd=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_rspamd-vol-1)
dockerVolumePostfix=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_postfix-vol-1)
dockerVolumeRedis=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_redis-vol-1)
dockerVolumeCrypt=$(docker volume inspect -f '{{ .Mountpoint }}' ${COMPOSE_PROJECT_NAME}_crypt-vol-1)


### Create sqlDump temporary directory and sqlDumpFile name
sqlDumpDir=$( mktemp -d )
sqlDumpFile="backup-`date +%Y%m%d_%H%M%S`.sql"
echo -e "${info}[$(stamp)] -- [INFO] mySQL dump file will be stored" \
    "at: ${lit}${sqlDumpDir}/${sqlDumpFile}${normal}" >> "$logFile"


### 503 error page: If you dont' plan on using the auto-copied 503 then comment
### this entire section starting with '--- Begin 503 section ---' until
### '--- End 503 section ---' to suppress generated warnings

### --- Begin 503 section ---

## Check if webroot has been specified, if not, skip this entire section since there is nowhere to copy the 503 file.
if [ -z "$webroot" ]; then
    # no webroot path provided
    echo -e "${info}[$(stamp)] -- [INFO] ${warn503} --${normal}" \
        >> "$logFile"
    exitWarn+=("[$(stamp)]_5031")
    clean503=0
else
    # verify webroot actually exists
    checkExist fd "$webroot"
    checkResult="$?"
    if [ "$checkResult" = "1" ]; then
        # webroot directory specified could not be found
        echo -e "${info}[$(stamp)] -- [INFO] ${warn503} --${normal}" \
            >> "$logFile"
        exitWarn+=("[$(stamp)]_5032")
        clean503=0
    else
        # webroot exists
        echo -e "${op}[$(stamp)] Using webroot: ${lit}${webroot}${normal}" \
            >> "$logFile"
        # Verify 503 file existance at given path
        checkExist ff "$err503Path"
        checkResult="$?"
        if [ "$checkResult" = "1" ]; then
            # 503 file could not be found
            echo -e "${info}[$(stamp)] -- [INFO] ${warn503} --${normal}" \
                >> "$logFile"
            exitWarn+=("[$(stamp)]_5033")
            clean503=0
        else
            # 503 file exists and webroot is valid. Let's copy it!
            echo -e "${op}[$(stamp)] ${err503File} found at ${lit}${err503Path}" \
                "${normal}" >> "$logFile"
            echo -e "${op}[$(stamp)] Copying 503 error page to webroot..." \
                "${normal}" >> "$logFile"
            cp "${err503Path}" "$webroot/" >> "$logFile" 2>&1
            copyResult="$?"
            # verify copy was successful
                if [ "$copyResult" = "1" ]; then
                    # copy was unsuccessful
                    echo -e "${info}[$(stamp)] -- [INFO] ${warn503} --${normal}" \
                        >> "$logFile"
                    exitWarn+=("[$(stamp)]_5035")
                    clean503=0
                else
                # copy was successful
                echo -e "${info}[$(stamp)] -- [INFO] 503 error page" \
                    "successfully copied to webroot --${normal}" >> "$logFile"
                clean503=1
                fi
        fi
    fi
fi

### --- End 503 section ---


### Change directory to mailcowPath
cd "$mailcowPath"


### Stop postfix and dovecot so mailflow is stopped until backup is completed
## Stop postfix-mailcow container
operateDocker stop postfix
# process result
if [ "$dockerResultState" = "false" ] && [ "$dockerResultExit" -eq 0 ]; then
    echo -e "${info}[$(stamp)] -- [INFO] Postfix container stopped --${normal}" \
        >> "$logFile"
else
    exitError+=("[$(stamp)]_101")
    cleanup
    quit
fi
## Stop dovecot-mailcow container
operateDocker stop dovecot
# process result
if [ "$dockerResultState" = "false" ] && [ "$dockerResultExit" -eq 0 ]; then
    echo -e "${info}[$(stamp)] -- [INFO] Dovecot container stopped --${normal}" \
        >> "$logFile"
else
    exitError+=("[$(stamp)]_102")
    cleanup
    quit
fi


### Dump SQL
echo -e "${op}[$(stamp)] Dumping mailcow SQL database...${normal}" >> "$logFile"
docker-compose exec -T mysql-mailcow mysqldump --default-character-set=utf8mb4 \
    -u${DBUSER} -p${DBPASS} ${DBNAME} > "$sqlDumpDir/$sqlDumpFile" \
    2>> "$logFile"
dumpResult=$(docker-compose exec -T mysql-mailcow echo "$?")
## very mysqldump completed successfully
if [ "$dumpResult" = "0" ]; then
    echo -e "${info}[$(stamp)] -- [INFO] mySQLdump completed successfully --" \
        "${normal}" >> "$logFile"
else
    exitError+=("[$(stamp)]_201")
fi
## verify the dump file was actually written to disk
checkExist fs "$sqlDumpDir/$sqlDumpFile"
    checkResult="$?"
    if [ "$checkResult" = "0" ]; then
        echo -e "${ok}[$(stamp)] -- [SUCCESS] SQL successfully dumped --" \
            "${normal}" >> "$logFile"
    else
        exitError+=("[$(stamp)]_201")
    fi

### Save redis state
## Delete any existing redis dump file otherwise our file check will be useless
echo -e "${op}[$(stamp)] Cleaning up old redis state backup...${normal}" \
    >> "$logFile"
checkExist ff "$dockerVolumeRedis/dump.rdb"
    checkResult="$?"
    if [ "$checkResult" = "0" ]; then
        echo -e "${lit}[$(stamp)] Old redis backup found. ${op}Deleting..." \
            "${normal}" >> "$logFile"
        rm -f "$dockerVolumeRedis/dump.rdb" 2>> "$logFile"
        echo -e "${op}[$(stamp)] ...done${normal}" >> "$logFile"
    else
        echo -e "${op}[$(stamp)] No old redis backup found${normal}" \
            >> "$logFile"
    fi
## Export redis
echo -e "${op}[$(stamp)] Saving redis state information...${normal}" >> "$logFile"
docker-compose exec -T redis-mailcow redis-cli save >> "$logFile" 2>&1
saveResult=$(docker-compose exec -T redis-mailcow echo "$?")
# verify save operation completed successfully
if [ "$saveResult" = "0" ]; then
    echo -e "${info}[$(stamp)] -- [INFO] redis save-state successful --" \
        "${normal}" >> "$logFile"
else
    exitError+=("[$(stamp)]_202")
fi
## verify save-file written to disk
checkExist fs "$dockerVolumeRedis/dump.rdb"
    checkResult="$?"
    if [ "$checkResult" = "0" ]; then
        echo -e "${ok}[$(stamp)] -- [SUCCESS] redis state saved --${normal}" \
        >> "$logFile"
    else
        exitError+=("[$(stamp)]_202")
    fi


### Call borgbackup to copy actual files
echo -e "${op}[$(stamp)] Pre-backup tasks completed, calling borgbackup..." \
    "${normal}" >> "$logFile"

## Get borgbackup settings and repo details
# read definition file and map to array variable
mapfile -t borgConfig < "$borgDetails"
## check if any required borg configuration variables in defintion file are
## empty and exit with error, otherwise, map array items to variables
# check: borg base directory
echo -e "${op}[$(stamp)] Verifying supplied borg configuration variables..." \
    "${normal}" >> "$logFile"
if [ -z "${borgConfig[0]}" ]; then
    exitError+=("[$(stamp)]_210")
    cleanup
    quit
else
    # verify the path actually exists
    checkExist fd "${borgConfig[0]}"
    checkResult="$?"
    if [ "$checkResult" = "1" ]; then
        # borg base directory specified could not be found
        exitError+=("[$(stamp)]_210")
        cleanup
        quit
    fi
    echo -e "${op}[$(stamp)] Borg base dir... OK${normal}" >> "$logFile"
    export BORG_BASE_DIR="${borgConfig[0]%/}"
fi
# check: path to SSH keyfile
if [ -z "${borgConfig[1]}" ]; then
    exitError+=("[$(stamp)]_211")
    cleanup
    quit
else
    checkExist ff "${borgConfig[1]}"
    checkResult="$?"
    if [ "$checkResult" = 1 ]; then
        # SSH keyfile specified could not be found
        exitError+=("[$(stamp)]_211")
        cleanup
        quit
    fi
    echo -e "${op}[$(stamp)] Borg SSH key... OK${normal}" >> "$logFile"
    export BORG_RSH="ssh -i ${borgConfig[1]}"
fi
# check: name of borg repo
if [ -z "${borgConfig[2]}" ]; then
    exitError+=("[$(stamp)]_212")
    cleanup
    quit
else
    echo -e "${op}[$(stamp)] Borg REPO name... OK${normal}" >> "$logFile"
    export BORG_REPO="${borgConfig[2]}"
fi
# repo password
if [ -n "${borgConfig[3]}" ]; then
    echo -e "${op}[$(stamp)] Borg SSH/REPO password... OK${normal}" >> "$logFile"
    export BORG_PASSPHRASE="${borgConfig[3]}"
else
    exitWarn+=("[$(stamp)]_2111")
    # if the password was omitted by mistake, export a dummy password so borg
    # fails with an error instead of sitting and waiting for input
    export BORG_PASSPHRASE="DummyPasswordSoBorgFails"
fi
# additional files to be backed up
borgXtra="${borgConfig[4]}"
# file with pattern definition for excluded files
borgExclude="${borgConfig[5]}"
# parameters for borg prune
borgPrune="${borgConfig[6]}"
# export: borg remote path (if not blank)
if [ -n "${borgConfig[7]}" ]; then
    echo -e "${op}[$(stamp)] Borg REMOTE path... OK${normal}" >> "$logFile"
    export BORG_REMOTE_PATH="${borgConfig[7]}"
else
    exitWarn+=("[$(stamp)]_2112")
fi

## If borgXtra exists, map contents to an array variable
if [ -n "$borgXtra" ]; then
    echo -e "${op}[$(stamp)] Processing referenced extra files list for" \
        "borgbackup to include in backup${normal}" >> "$logFile"
    checkExist ff "$borgXtra"
    checkResult="$?"
    if [ "$checkResult" = "0" ]; then
        echo -e "${op}[$(stamp)] Found ${lit}${borgXtra}${normal}" >> "$logFile"
        mapfile -t xtraFiles < "$borgXtra"
        echo -e "${op}[$(stamp)] Processed extra files list for inclusion in" \
            "borgbackup${normal}" >> "$logFile"
    else
        exitWarn+=("[$(stamp)]_2113")
    fi
else
    # no extra locations specified
    echo -e "${op}[$(stamp)] No additional locations specified for backup." \
        "Only Mailcow data and config files will be backed up.${normal}" \
            >> "$logFile"
    exitWarn+=("[$(stamp)]_2116")
fi

## Check if borgExclude exists since borg will throw an error if it's missing
if [ -n "$borgExclude" ]; then
    checkExist ff "$borgExclude"
    checkResult="$?"
    if [ "$checkResult" = "0" ]; then
            echo -e "${op}[$(stamp)] Found ${lit}${borgExclude}${normal}" \
                >> "$logFile"
    else
        # file not found, unset the variable so it's like it was not specified
        # in the first place and continue with backup
        unset borgExclude
        exitWarn+=("[$(stamp)]_2114")
    fi
else
    echo -e "${op}[$(stamp)] Exclusion pattern file not specified." \
        "No exclusions will be processed${normal}" >> "$logFile"
fi


## Export TMPDIR environment variable for borg via python
## Python requires a writable temporary directory when unpacking borg and
## executing commands.  This defaults to /tmp but many systems mount /tmp with
## the 'noexec' option for security.  Thus, we will use/create a 'tmp' folder
## within the BORG_BASE_DIR and instruct python to use that instead of /tmp
# check if BORG_BASE_DIR/tmp exists, if not, create it
echo -e "${op}[$(stamp)] Checking for tmp directory at ${lit}${BORG_BASE_DIR}" \
    "${normal}" >> "$logFile"
checkExist fd "$BORG_BASE_DIR/tmp"
checkResult="$?"
if [ "$checkResult" = "1" ]; then
    # folder not found
    echo -e "${op}[$(stamp)] tmp folder not found... creating${lit}" \
        "${BORG_BASE_DIR}/tmp${normal}" >> "$logFile"
    mkdir "$BORG_BASE_DIR/tmp" 2>> "$logFile"
    # verify folder created
    checkExist fd "$BORG_BASE_DIR/tmp"
    checkResult="$?"
    if [ "$checkResult" = "0" ]; then
        # folder exists
        echo -e "${op}[$(stamp)] tmp folder created within borg base directory" \
            "${normal}" >> "$logFile"
    else
        # problem creating folder and script will exit
        exitError+=("[$(stamp)]_215")
        cleanup
        quit
    fi
else
    # folder found
    echo -e "${op}[$(stamp)] tmp folder found within borg base directory" \
        "${normal}" >> "$logFile"
fi
# export TMPDIR environment variable
export TMPDIR="${BORG_BASE_DIR}/tmp"


## Generate and execute borg
# commandline depends on whether borgExclude is empty or not
if [ -z "$borgExclude" ]; then
    # borgExclude is empty
    echo -e "${bold}${op}[$(stamp)] Executing borg without exclusions${normal}" \
        >> "$logFile"
    borg --show-rc create ${borgCreateParams} ::`date +%Y-%m-%d_%H%M%S` \
        "${xtraFiles[@]}" \
        "${sqlDumpDir}" \
        "${dockerVolumeMail}" "${dockerVolumeRspamd}" "${dockerVolumePostfix}" \
        "${dockerVolumeRedis}" "${dockerVolumeCrypt}" \
        2>> "$logFile"
else
    # borgExclude is not empty
    echo -e "${bold}${op}[$(stamp)] Executing borg with exclusions${normal}" \
        >> "$logFile"
    borg --show-rc create ${borgCreateParams} --exclude-from "${borgExclude}" \
        ::`date +%Y-%m-%d_%H%M%S` \
        "${xtraFiles[@]}" \
        "${sqlDumpDir}" \
        "${dockerVolumeMail}" "${dockerVolumeRspamd}" "${dockerVolumePostfix}" \
        "${dockerVolumeRedis}" "${dockerVolumeCrypt}" \
        2>> "$logFile"
fi

## Check status of borg operation
borgResult="$?"
if [ "$borgResult" -eq 0 ]; then
    echo -e "${ok}[$(stamp)] -- [SUCCESS] Borg backup completed successfully --" \
        "${normal}" >> "$logFile"
elif [ "$borgResult" -eq 1 ]; then
    exitWarn+=("[$(stamp)]_2200")
elif [ "$borgResult" -ge 2 ]; then
    exitError+=("[$(stamp)]_220")
    cleanup
    quit
else
    exitWarn+=("[$(stamp)]_2201")
fi

## Generate and execute borg prune
# command depends on whether or not parameters have been defined
if [ -n "$borgPrune" ]; then
    # parameters defined
    echo -e "${bold}${op}[$(stamp)] Executing borg prune operation${normal}" \
        >> "$logFile"
    borg prune --show-rc -v ${borgPruneParams} ${borgPrune} \
        2>> "$logFile"
    # check return-status
    pruneResult="$?"
    if [ "$pruneResult" -eq 0 ]; then
        echo -e "${ok}[$(stamp)] -- [SUCCESS] Borg prune completed successfully" \
            "--${normal}" >> "$logFile"
    elif [ "$pruneResult" -eq 1 ]; then
        exitWarn+=("[$(stamp)]_2210")
    elif [ "$pruneResult" -ge 2 ]; then
        exitError+=("[$(stamp)]_221")
    else
        exitWarn+=("[$(stamp)]_2212")
    fi
else
    # parameters not defined... skip pruning
    exitWarn+=("[$(stamp)]_2115")
fi


### borgbackup completed
echo -e "${op}[$(stamp)] Borgbackup completed... begin cleanup" \
    "${normal}" >> "$logFile"


### Exit script
echo -e "${bold}${op}[$(stamp)] ***Normal exit process***${normal}" \
    >> "$logFile"
cleanup
echo -e "${bold}${ok}[$(stamp)] -- [SUCCESS] All processes completed" \
    "successfully --${normal}" >> "$logFile"
quit

# This code should not be executed since the 'quit' function should terminate
# this script.  Therefore, exit with code 99 if we get to this point.
exit 99
