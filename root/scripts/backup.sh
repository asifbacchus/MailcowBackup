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
stamp="[`date +%Y-%m-%d` `date +%H:%M:%S`]"


### Functions ###

### scriptHelp -- display usage information for this script
function scriptHelp {
    echo -e "${bold}${note}\n${scriptName} usage instructions:\n${normal}"
    echo -e "${default}This script performs a backup of your NextCloud system"
    echo -e "assuming a fairly standard set up such as outlined at"
    echo -e "${lit}https://mytechiethoughts.com${default}.  Full details about"
    echo -e "this script can be found at that site."
    echo -e "${bold}\nThe script performs the following tasks:${normal}${default}"
    echo -e "1. Puts NextCloud in maintenance mode."
    echo -e "2. Optionally copies a 503 error page to your webroot."
    echo -e "3. Dumps SQL to a temporary directory."
    echo -e "4. Invokes borgbackup to backup your SQL info, NextCloud program"
    echo -e "\tand data files along with any other files you specify."
    echo -e "5. Removes temp files, the 503 error page and restores"
    echo -e "\tNextCloud to operational status."
    echo -e "\nThe readme file included in this script's git contains detailed"
    echo -e "usage information. The following is a brief summary:\n"
    echo -e "${bold}${note}Mandatory parameters:${normal}${default}"
    echo -e "${lit}\n-d, NextCloud data directory${default}"
    echo -e "This is the physical location of your NextCloud data."
    echo -e "${lit}\n-n, NextCloud webroot${default}"
    echo -e "This is the location of the actual NextCloud web files (php & html"
    echo -e ",etc.), usually within your NGINX or Apache webroot."
    echo -e "${lit}\n-u, NGINX/Apache webuser account${default}"
    echo -e "The webuser account NGINX/Apache (and thus, NextCloud) are running"
    echo -e "under.  Some actions must run as this user due to file ownership"
    echo -e "restrictions."
    echo -e "${bold}${note}\nOptional parameters:${normal}${default}"
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
    echo -e "${lit}\n-l, Location to save log file${default}"
    echo -e "This script writes a detailed log file of all activities.  It is" 
    echo -e "structured in an way easy for log parsers (like Logwatch) to read."
    echo -e "${info}Default: ScriptPath/ScriptName.log${default}"
    echo -e "${lit}\n-s, Location of file with mySQL details${default}"
    echo -e "FULL PATH to the plain text file containing all information needed"
    echo -e "to connect to your mySQL (mariaDB) server and NextCloud database."
    echo -e "Details on the structure of this file are in the readme and on ${lit}"
    echo -e "https://mytechiethoughts.com${default}"
    echo -e "${info}Default: ScriptPath/nc_sql.details${default}"
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

### quit -- exit the script after logging any errors, warnings, etc.
function quit {
    # list generated warnings, if any
    if [ ${#exitWarn[@]} -gt 0 ]; then
        echo -e "${warn}${scriptName} generated the following warnings:" \
            "${normal}" >> "$logFile"
        for warnCode in "${exitWarn[@]}"; do
            echo -e "${warn}-- [WARNING] ${warningExplain[$warnCode]}" \
                "(code: ${warnCode}) --${normal}" >> "$logFile"
        done
    fi
    if [ -z "${exitError}" ]; then
        # exit cleanly
        echo -e "${note}${stamp} -- ${scriptName} completed" \
            "--${normal}" >> "$logFile"
        exit 0
    else
        # list generated errors and explanations then exit script with code 2
        echo -e "${err}${scriptName} generated the following errors:" \
            "${normal}" >> "$logFile"
        for errCode in "${exitError[@]}"; do
            echo -e "${err}-- [ERROR] ${errorExplain[$errCode]}" \
                "(code: ${errCode}) --$normal" >> "$logFile"
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

### ncMaint - pass requested mode change type to NextCloud occ
function ncMaint {
    sudo -u ${webUser} php ${ncroot}/occ maintenance:mode --$1 \
        >> "$logFile" 2>&1
    maintResult="$?"
    return "$maintResult"
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
        exitWarn+=('111')
    else
        # directory removed
        echo -e "${op}${stamp} Removed SQL temp directory${normal}" \
            >> "$logFile"
    fi

    ## remove 503 error page
    # check value of 'clean503' to see if this is necessary (=1) otherwise, skip
    if [ "$clean503" = "1" ]; then
        # proceed with cleanup
        echo -e "${op}${stamp} Removing 503 error page..." >> "$logFile"
        rm -f "$webroot/$err503File" >> "$logFile" 2>&1
        # verify file is actually gone
        checkExist ff "$webroot/$err503File"
        checkResult="$?"
        if [ "$checkResult" = "0" ]; then
            # file still exists
            exitWarn+=('5030')
        else
            # file removed
            echo -e "${info}${stamp} -- [INFO] 503 page removed from webroot" \
                "--${normal}" >> "$logFile"
        fi
    else
        echo -e "${op}${stamp} 503 error page never copied to webroot," \
            "nothing to cleanup" >> "$logFile"
    fi

    ## Exit NextCloud maintenance mode regardless of current status
    ncMaint off
    # check if successful
    if [ "$maintResult" = "0" ]; then
        echo -e "${info}${stamp} -- [INFO] NextCloud now in regular" \
                "operating mode --${normal}" >> "$logFile"
        else
            exitError+=('101')
            quit
    fi
}

### End of Functions ###


### Default parameters

# store the logfile in the same directory as this script using the script's name
# with the extension .log
scriptPath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
scriptName="$( basename ${0} )"
logFile="$scriptPath/${scriptName%.*}.log"

# set default 503 error page name and location in scriptPath
err503Path="$scriptPath/503.html"
err503File="${err503Path##*/}"

# set default sqlDetails path to scriptPath
sqlDetails="$scriptPath/nc_sql.details"

# set default borgDetails path to scriptPath
borgDetails="$scriptPath/nc_borg.details"

# set borg parameters to 'normal' verbosity
borgCreateParams='--stats'
borgPruneParams='--list'


### Set script parameters to null and initialize array variables
unset PARAMS
unset sqlDumpDir
unset webroot
unset ncRoot
unset webUser
unset clean503
unset sqlParams
unset ncDataDir
unset borgXtra
unset borgExclude
unset borgPrune
unset BORG_BASE_DIR
unset BORG_RSH
unset BORG_REPO
unset BORG_PASSPHRASE
unset BORG_REMOTE_PATH
unset TMPDIR
exitError=()
errorExplain=()
exitWarn=()
warningExplain=()
borgConfig=()
xtraFiles=()

### Error codes
errorExplain[100]="Could not put NextCloud into maintenance mode"
errorExplain[101]="Could not exit NextCloud maintenance mode"
errorExplain[200]="Could not dump NextCloud SQL database"
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
warningExplain[2116]="No additional locations are specified for inclusion in backup. ONLY NextCloud DATA will be backed up (no configuration, etc). If this is unintentional, check the inclusion file referenced in your borgbackup settings"
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
while getopts ':l:n:u:v5:w:s:b:d:' PARAMS; do
    case "$PARAMS" in
        l)
            # use provided location for logFile
            logFile="${OPTARG}"
            ;;
        n)
            # NextCloud webroot
            ncRoot="${OPTARG%/}"
            ;;
        u)
            # webuser
            webUser="${OPTARG}"
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
        s)
            # path to file containing SQL login details
            sqlDetails="${OPTARG%/}"
            ;;
        b)
            # path to file containing borgbackup settings and details
            borgDetails="${OPTARG%/}"
            ;;
        d)
            # nextcloud data directory
            ncDataDir="${OPTARG%/}"
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
    exit 2
fi

## Check NextCloud webroot
# Ensure NextCloud webroot is provided
if [ -z "$ncRoot" ]; then
    echo -e "\n${err}The NextCloud webroot must be specified (-n parameter)" \
        "${normal}\n"
    exit 1
# Ensure NextCloud webroot directory exists
elif [ -n "$ncRoot" ]; then
    checkExist fd "$ncRoot"
    checkResult="$?"
    if [ "$checkResult" = "1" ]; then
        # Specified NextCloud webroot directory could not be found
        echo -e "\n${err}The provided NextCloud webroot directory" \
            "(-n parameter) does not exist.${normal}\n"
        exit 1
    fi
fi

## Check NextCloud webuser account
# Ensure NextCloud webuser account is provided
if [ -z "$webUser" ]; then
    echo -e "\n${err}The webuser account running NextCloud must be provided" \
        "(-u parameter)${normal}\n"
    exit 1
# Check if supplied webUser account exists
elif [ -n "$webUser" ]; then
    user_exists=$(id -u $webUser > /dev/null 2>&1; echo $?)
    if [ $user_exists -ne 0 ]; then        
        echo -e "\n${err}The supplied webuser account (-u parameter) does not" \
            "exist.${normal}\n"
        exit 1
    fi
fi

## Ensure sqlDetails file exists
checkExist ff "$sqlDetails"
checkResult="$?"
if [ "$checkResult" = "1" ]; then
    # sqlDetails file cannot be found
    echo -e "\n${err}The file containing your SQL details does not exist" \
        "(-s parameter)${normal}\n"
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

## Check NextCloud data directory
# Ensure NextCloud data directory is provided
if [ -z "$ncDataDir" ]; then
    echo -e "\n${err}The NextCloud data directory must be specified" \
        "(-d parameter)${normal}\n"
    exit 1
# Ensure NextCloud data directory exists
elif [ -n "$ncDataDir" ]; then
    checkExist fd "$ncDataDir"
    checkResult="$?"
    if [ "$checkResult" = "1" ]; then
        # Specified NextCloud data directory could not be found
        echo -e "\n${err}The provided NextCloud data directory" \
            "(-d parameter) does not exist.${normal}\n"
        exit 1
    fi
fi


### Log start of script operations
echo -e "${note}${stamp}-- Start $scriptName execution ---${normal}" \
    >> "$logFile"


### Export logFile variable for use by Borg
export logFile="$logFile"


### Create sqlDump temporary directory and sqlDumpFile name
sqlDumpDir=$( mktemp -d )
sqlDumpFile="backup-`date +%Y%m%d_%H%M%S`.sql"
echo -e "${info}${stamp} -- [INFO] mySQL dump file will be stored" \
    "at: ${lit}${sqlDumpDir}/${sqlDumpFile}${normal}" >> "$logFile"


### 503 error page: If you dont' plan on using the auto-copied 503 then comment
### this entire section starting with '--- Begin 503 section ---' until
### '--- End 503 section ---' to suppress generated warnings

### --- Begin 503 section ---

## Check if webroot has been specified, if not, skip this entire section since there is nowhere to copy the 503 file.
if [ -z "$webroot" ]; then
    # no webroot path provided
    echo -e "${info}${stamp} -- [INFO] ${warn503} --${normal}" \
        >> "$logFile"
    exitWarn+=('5031')
    clean503=0
else
    # verify webroot actually exists
    checkExist fd "$webroot"
    checkResult="$?"
    if [ "$checkResult" = "1" ]; then
        # webroot directory specified could not be found
        echo -e "${info}${stamp} -- [INFO] ${warn503} --${normal}" \
            >> "$logFile"
        exitWarn+=('5032')
        clean503=0
    else
        # webroot exists
        echo -e "${op}${stamp} Using webroot: ${lit}${webroot}${normal}" \
            >> "$logFile"
        # Verify 503 file existance at given path
        checkExist ff "$err503Path"
        checkResult="$?"
        if [ "$checkResult" = "1" ]; then
            # 503 file could not be found
            echo -e "${info}${stamp} -- [INFO] ${warn503} --${normal}" \
                >> "$logFile"
            exitWarn+=('5033')
            clean503=0
        else
            # 503 file exists and webroot is valid. Let's copy it!
            echo -e "${op}${stamp} ${err503File} found at ${lit}${err503Path}" \
                "${normal}" >> "$logFile"
            echo -e "${op}${stamp} Copying 503 error page to webroot..." \
                "${normal}" >> "$logFile"
            cp "${err503Path}" "$webroot/" >> "$logFile" 2>&1
            copyResult="$?"
            # verify copy was successful
                if [ "$copyResult" = "1" ]; then
                    # copy was unsuccessful
                    echo -e "${info}${stamp} -- [INFO] ${warn503} --${normal}" \
                        >> "$logFile"
                    exitWarn+=('5035')
                    clean503=0
                else
                # copy was successful
                echo -e "${info}${stamp} -- [INFO] 503 error page" \
                    "successfully copied to webroot --${normal}" >> "$logFile"
                clean503=1
                fi
        fi
    fi
fi

### --- End 503 section ---


### Put NextCloud in maintenance mode
ncMaint on
# check if successful
if [ "$maintResult" = "0" ]; then
    echo -e "${info}${stamp} -- [INFO] NextCloud now in maintenance mode --" \
        "${normal}" >> "$logFile"
else
    exitError+=('100')
    cleanup
    quit
fi


### Get SQL info from sqlDetails
mapfile -t sqlParams < "$sqlDetails"


### Dump SQL
echo -e "${op}${stamp} Dumping NextCloud SQL database...${normal}" >> "$logFile"
mysqldump --single-transaction -h"${sqlParams[0]}" -u"${sqlParams[1]}" \
    -p"${sqlParams[2]}" "${sqlParams[3]}" > "${sqlDumpDir}/${sqlDumpFile}" \
    2>> "$logFile"
# verify
dumpResult="$?"
if [ "$dumpResult" = "0" ]; then
    echo -e "${ok}${stamp} -- [SUCCESS] SQL dumped successfully --${normal}" \
        >> "$logFile"
else
    exitError+=('200')
    cleanup
    quit
fi

### Call borgbackup to copy actual files
echo -e "${op}${stamp} Pre-backup tasks completed, calling borgbackup..." \
    "${normal}" >> "$logFile"

## Get borgbackup settings and repo details
# read definition file and map to array variable
mapfile -t borgConfig < "$borgDetails"
## check if any required borg configuration variables in defintion file are
## empty and exit with error, otherwise, map array items to variables
# check: borg base directory
echo -e "${op}${stamp} Verifying supplied borg configuration variables..." \
    "${normal}" >> "$logFile"
if [ -z "${borgConfig[0]}" ]; then
    exitError+=('210')
    cleanup
    quit
else
    # verify the path actually exists
    checkExist fd "${borgConfig[0]}"
    checkResult="$?"
    if [ "$checkResult" = "1" ]; then
        # borg base directory specified could not be found
        exitError+=('210')
        cleanup
        quit
    fi
    echo -e "${op}${stamp} Borg base dir... OK${normal}" >> "$logFile"
    export BORG_BASE_DIR="${borgConfig[0]%/}"
fi
# check: path to SSH keyfile
if [ -z "${borgConfig[1]}" ]; then
    exitError+=('211')
    cleanup
    quit
else
    checkExist ff "${borgConfig[1]}"
    checkResult="$?"
    if [ "$checkResult" = 1 ]; then
        # SSH keyfile specified could not be found
        exitError+=('211')
        cleanup
        quit
    fi
    echo -e "${op}${stamp} Borg SSH key... OK${normal}" >> "$logFile"
    export BORG_RSH="ssh -i ${borgConfig[1]}"
fi
# check: name of borg repo
if [ -z "${borgConfig[2]}" ]; then
    exitError+=('212')
    cleanup
    quit
else
    echo -e "${op}${stamp} Borg REPO name... OK${normal}" >> "$logFile"
    export BORG_REPO="${borgConfig[2]}"
fi
# repo password
if [ -n "${borgConfig[3]}" ]; then
    echo -e "${op}${stamp} Borg SSH/REPO password... OK${normal}" >> "$logFile"
    export BORG_PASSPHRASE="${borgConfig[3]}"
else
    exitWarn+=('2111')
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
    echo -e "${op}${stamp} Borg REMOTE path... OK${normal}" >> "$logFile"
    export BORG_REMOTE_PATH="${borgConfig[7]}"
else
    exitWarn+=('2112')
fi

## If borgXtra exists, map contents to an array variable
if [ -n "$borgXtra" ]; then
    echo -e "${op}${stamp} Processing referenced extra files list for" \
        "borgbackup to include in backup${normal}" >> "$logFile"
    checkExist ff "$borgXtra"
    checkResult="$?"
    if [ "$checkResult" = "0" ]; then
        echo -e "${op}${stamp} Found ${lit}${borgXtra}${normal}" >> "$logFile"
        mapfile -t xtraFiles < "$borgXtra"
        echo -e "${op}${stamp} Processed extra files list for inclusion in" \
            "borgbackup${normal}" >> "$logFile"
    else
        exitWarn+=('2113')
    fi
else
    # no extra locations specified
    echo -e "${op}${stamp} No additional locations specified for backup." \
        "Only NextCloud data files will be backed up${normal}" >> "$logFile"
    exitWarn+=('2116')
fi

## Check if borgExclude exists since borg will throw an error if it's missing
if [ -n "$borgExclude" ]; then
    checkExist ff "$borgExclude"
    checkResult="$?"
    if [ "$checkResult" = "0" ]; then
            echo -e "${op}${stamp} Found ${lit}${borgExclude}${normal}" \
                >> "$logFile"
    else
        # file not found, unset the variable so it's like it was not specified
        # in the first place and continue with backup
        unset borgExclude
        exitWarn+=('2114')
    fi
else
    echo -e "${op}${stamp} Exclusion pattern file not specified." \
        "No exclusions will be processed${normal}" >> "$logFile"
fi


## Export TMPDIR environment variable for borg via python
## Python requires a writable temporary directory when unpacking borg and
## executing commands.  This defaults to /tmp but many systems mount /tmp with
## the 'noexec' option for security.  Thus, we will use/create a 'tmp' folder
## within the BORG_BASE_DIR and instruct python to use that instead of /tmp
# check if BORG_BASE_DIR/tmp exists, if not, create it
echo -e "${op}${stamp} Checking for tmp directory at ${lit}${BORG_BASE_DIR}" \
    "${normal}" >> "$logFile"
checkExist fd "$BORG_BASE_DIR/tmp"
checkResult="$?"
if [ "$checkResult" = "1" ]; then
    # folder not found
    echo -e "${op}${stamp} tmp folder not found... creating${lit}" \
        "${BORG_BASE_DIR}/tmp${normal}" >> "$logFile"
    mkdir "$BORG_BASE_DIR/tmp" 2>> "$logFile"
    # verify folder created
    checkExist fd "$BORG_BASE_DIR/tmp"
    checkResult="$?"
    if [ "$checkResult" = "0" ]; then
        # folder exists
        echo -e "${op}${stamp} tmp folder created within borg base directory" \
            "${normal}" >> "$logFile"
    else
        # problem creating folder and script will exit
        exitError+=('215')
        cleanup
        quit
    fi
else
    # folder found
    echo -e "${op}${stamp} tmp folder found within borg base directory" \
        "${normal}" >> "$logFile"
fi
# export TMPDIR environment variable
export TMPDIR="${BORG_BASE_DIR}/tmp"


## Generate and execute borg
# commandline depends on whether borgExclude is empty or not
if [ -z "$borgExclude" ]; then
    # borgExclude is empty
    echo -e "${bold}${op}${stamp} Executing borg without exclusions${normal}" \
        >> "$logFile"
    borg --show-rc create ${borgCreateParams} ::`date +%Y-%m-%d_%H%M%S` \
        ${xtraFiles[@]} \
        ${sqlDumpDir} ${ncDataDir} \
        2>> "$logFile"
else
    # borgExclude is not empty
    echo -e "${bold}${op}${stamp} Executing borg with exclusions${normal}" \
        >> "$logFile"
    borg --show-rc create ${borgCreateParams} --exclude-from ${borgExclude} \
        ::`date +%Y-%m-%d_%H%M%S` \
        ${xtraFiles[@]} \
        ${sqlDumpDir} ${ncDataDir} \
        2>> "$logFile"
fi

## Check status of borg operation
borgResult="$?"
if [ "$borgResult" -eq 0 ]; then
    echo -e "${ok}${stamp} -- [SUCCESS] Borg backup completed successfully --" \
        "${normal}" >> "$logFile"
elif [ "$borgResult" -eq 1 ]; then
    exitWarn+=('2200')
elif [ "$borgResult" -ge 2 ]; then
    exitError+=('220')
    cleanup
    quit
else
    exitWarn+=('2201')
fi

## Generate and execute borg prune
# command depends on whether or not parameters have been defined
if [ -n "$borgPrune" ]; then
    # parameters defined
    echo -e "${bold}${op}${stamp} Executing borg prune operation${normal}" \
        >> "$logFile"
    borg prune --show-rc -v ${borgPruneParams} ${borgPrune} \
        2>> "$logFile"
    # check return-status
    pruneResult="$?"
    if [ "$pruneResult" -eq 0 ]; then
        echo -e "${ok}${stamp} -- [SUCCESS] Borg prune completed successfully" \
            "--${normal}" >> "$logFile"
    elif [ "$pruneResult" -eq 1 ]; then
        exitWarn+=('2210')
    elif [ "$pruneResult" -ge 2 ]; then
        exitError+=('221')
    else
        exitWarn+=('2212')
    fi
else
    # parameters not defined... skip pruning
    exitWarn+=('2115')
fi


### borgbackup completed
echo -e "${op}${stamp} Borgbackup completed... begin cleanup" \
    "${normal}" >> "$logFile"


### Exit script
echo -e "${bold}${op}${stamp} ***Normal exit process***${normal}" \
    >> "$logFile"
cleanup
echo -e "${bold}${ok}${stamp} -- [SUCCESS] All processes completed" \
    "successfully --${normal}" >> "$logFile" 
quit

# This code should not be executed since the 'quit' function should terminate
# this script.  Therefore, exit with code 99 if we get to this point.
exit 99
