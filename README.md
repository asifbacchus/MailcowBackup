# Mailcow Backup Using borgbackup <!-- omit in toc -->

This script automates backing up your Mailcow installation using borgbackup
and a remote ssh-capable storage system.  I suggest using rsync.net since they
have great speeds and a special pricing structure for borgbackup/attic users
([details here](https://www.rsync.net/products/attic.html)).

This script automates the following tasks:

- Optionally copies a 503 error page to your webserver so users know when your
  server is unavailable due to backups being performed. The 503 file is removed
  when the backup is completed so users can login again
- Dumps the Mailcow mySQL database and adds it to the backup
- Handles stopping and re-starting mail-flow containers (postfix and dovecot) so
  everything is in a consistent state during the backup
- Allows you to specify additional files you want backed up
- Allows you to specify files/directories to exclude from your backups
- Runs 'borg prune' to make sure you are trimming old backups on your schedule
- Creates a clear, easy to parse log file so you can keep an eye on your backups
  and any errors/warnings

## Contents <!-- omit in toc -->

- [Installation/copying](#installationcopying)
- [Environment notes](#environment-notes)
- [Why this script must be run as root](#why-this-script-must-be-run-as-root)
- [Script parameters](#script-parameters)
    - [Optional parameters](#optional-parameters)
        - [Docker container STOP timeout before error: -1 _number_](#docker-container-stop-timeout-before-error--1-_number_)
        - [Docker container START timeout before error: -2 _number_](#docker-container-start-timeout-before-error--2-_number_)
        - [Path to 503 error page: -5 _/path/to/filename.html_](#path-to-503-error-page--5-_pathtofilenamehtml_)
        - [Path to borg details file: -b _/path/to/filename.file_](#path-to-borg-details-file--b-_pathtofilenamefile_)
        - [File name of docker-compose configuration file: -d _filename.file_](#file-name-of-docker-compose-configuration-file--d-_filenamefile_)
        - [Log file location: -l _/path/to/filename.file_](#log-file-location--l-_pathtofilenamefile_)
        - [File name of Mailcow master configuration file: -m _filename.file_](#file-name-of-mailcow-master-configuration-file--m-_filenamefile_)
        - [Verbose output from borg: -v (no arguments)](#verbose-output-from-borg--v-no-arguments)
        - [Path to webroot: -w _/path/to/webroot/_](#path-to-webroot--w-_pathtowebroot_)
- [Borg details file](#borg-details-file)
    - [Protect your borg details file](#protect-your-borg-details-file)
    - [borg specific entries (lines 1-4)](#borg-specific-entries-lines-1-4)
    - [additional files/directories to backup](#additional-filesdirectories-to-backup)
    - [exclusion patterns](#exclusion-patterns)
    - [prune timeframe options](#prune-timeframe-options)
    - [borg remote location](#borg-remote-location)
    - [Examples](#examples)
- [503 functionality](#503-functionality)
    - [Conditional forwarding by your webserver](#conditional-forwarding-by-your-webserver)
        - [NGINX](#nginx)
        - [Apache](#apache)
        - [Disabling 503 functionality altogether](#disabling-503-functionality-altogether)
- [Scheduling: Cron](#scheduling-cron)
- [The log file](#the-log-file)
    - [Using Logwatch](#using-logwatch)
    - [Remember to rotate your logs](#remember-to-rotate-your-logs)
- [Final notes](#final-notes)

## Installation/copying

Once you've either cloned this git or downloaded the release file, simply copy
the files within the archive to whatever location(s) that work for your setup.
I've stored the files in this git archive in a directory structure that should
match most default setups.  I suggest keeping the contents of the
*'/root/scripts'* folder in that location since the root user must execute the
script anyways.  If you edit the 503.html and mc_borg.details files in place,
then you don't have to specify their locations when running the script.

Remember to make the script executable!

```Bash
chmod +x backup.sh
```

In addition, you can rename this script file to anything you like.  The log file
will use that same name by default when naming itself and any mention of this
file in the logs will automatically use whatever name you choose to give it.

## Environment notes

The script is designed to be easy to use but still be flexible enough to
accommodate a wide range of Mailcow setups.  The script pulls nearly all it's
configuration from the Mailcow configuration files themselves, so it adapts to
nearly all customizations you may have in your environment.  The script accepts
several optional parameters to override its default or detected settings.  In
addition, it reads easy-to-edit external plain-text files for borg settings so
you don't have to weed through the script code to supply things like passwords.

**This script auto-detects the location of your Mailcow configuration file. If
you have multiple files on your system with the same name as the configuration
file, the script will likely get confused and exit with an error**

## Why this script must be run as root

This script must be run by the root user and will exit with an error if you try
running it otherwise.  This is because a default secured setup of borgbackup
contains things like the repository private key that are locked out to root user
access only.  In addition, the root user is guaranteed to have access to all
files you might want to backup.

## Script parameters

You can run the script with the *'-?'* parameter to access the built-in help
which explains the parameters.  However, the following is a more detailed
explanation of each parameter and how to use them. **Note that any parameters
needing a directory (webroot, log file location, etc.) can be entered with or
without the trailing '/' since it's stripped by the script anyways.**

General usage:

```Bash
/path/to/script/scriptname.sh -parameter argument -parameter argument ...
```

### Optional parameters

#### Docker container STOP timeout before error: -1 _number_

The amount of time, in seconds, to wait for a docker container to STOP
gracefully before aborting, logging the error and exiting the script.\
**Default: _120_**

#### Docker container START timeout before error: -2 _number_

The amount of time, in seconds, to wait for a docker container to START
before aborting, logging the error and exiting the script.\
**Default: _180_**

#### Path to 503 error page: -5 _/path/to/filename.html_

The path to an html file for the script to copy to your webroot during the
backup process.  This file can be scanned by your webserver and a 503 error can
be issued to users letting them know that your Mailcow is 'temporarily
unavailable' while being backed up.  A sample 503 page is included for you.

If you remove the default file or the one you specify is missing, a warning will
be issued by the script but, it will continue executing.  More details on the
503 notification can be found later in the [503
functionality](#503-functionality) section of this document.\
**Default: _scriptpath/503.html_**

#### Path to borg details file: -b _/path/to/filename.file_

This is a text file that lays out various borg options such as repo name,
password, additional files to include, exclusion patters, etc.  A sample file is
included for your reference.  More details, including the *required order* of
entries can be found later in this document in the [borg details
file](#borg-details-file) section.\
**Default: _scriptpath/mc_borg.details_**

#### File name of docker-compose configuration file: -d _filename.file_

This is the file name of your docker-compose configuration file that is used to
build/start/stop containers.  This script will only search for this file within
the same directory where your Mailcow configuration file is found.\
**Default: _docker-compose.yml_**

#### Log file location: -l _/path/to/filename.file_

If you have a particular place and filename you'd like this script to use for
it's log, then you can specify it using this parameter.  I would recommend
*'/var/log/backup.log'*. By default, the script will name the log file
*scriptname*.log and will save it in the same directory as the script itself.\
**Default: _scriptpath/scriptname.log_**

#### File name of Mailcow master configuration file: -m _filename.file_

This is the file name of the Mailcow master configuration file that was
generated after installation and contains all information needed to run Mailcow
(database user name, volume directory prefixes, etc.)  This script will search
your computer for either the default file name or the one you have provided.
Upon finding it, the script will derive the file path and use that as the path
in which to run all Mailcow/docker commands.  **Please do not have multiple
files on your system with this name, the script WILL get confused and exit with
an error.\
**Default: _mailcow.conf_**

#### Verbose output from borg: -v (no arguments)

By default, the script will ask borg to generate summary only output and record
that in the script's log file.  If you are running the backup for the first time
or are troubleshooting, you may want a detailed output of all files and their
changed/unchanged/excluded status from borg.  In that case, specify the -v
switch. **Note: This will make your log file very large very quickly since EVERY
file being backed up is written to the log.**

#### Path to webroot: -w _/path/to/webroot/_

This is the path to the directory your webserver is using as it's default root.
In other words, this is the directory that contains the html files served when
someone browses to your server.  The correct webroot depends greatly on your
particular setup.

If you directly connect to Mailcow via Docker, then your webroot is by default
*/opt/mailcow-dockerized/data/web*, unless you've made changes to your install
locations.  If you are running behind a reverse-proxy, then your webroot is your
webserver's webroot (*/var/www* or */usr/share/nginx/html*, for example).

This is used exclusively for 503 functionality since the script has to know
where to copy the 503 file.  If you don't want to use this functionality, you
can omit this parameter and the script will issue a warning and move on.  More
details can be found in the [503 functionality](#503-functionality) section
later in this document.

## Borg details file

This file contains all the data needed to access your borg remote data repo.
Each line must contain specific information in a specific order or **needs to be
blank if that data is not required**.  The sample file includes this data and
example entries.  The file must have the following information in the following
order:

    1. path to borg base directory **(required)**
    2. path to ssh private key for repo **(required)**
    3. connection string to remote repo **(required)**
    4. password for ssh key/repo **(required)**
    5. path to file listing additional files/directories to backup
    6. path to file containing borg-specific exclusion patterns
    7. prune timeframe options
    8. location of borg remote instance

### Protect your borg details file

This file contains information on how to access and decrypt your borg repo,
therefore, you **must** protect it.  You should lock it out for everyone but
your root user. Putting it in your root folder is not enough!  Run the following
commands to restrict access to the root user only (assuming filename is
*mc_borg.details*):

```Bash
chown root:root mc_borg.details   # make root the owner of this file
chmod 600 mc_borg.details   # grant access to root user only (read/write)
```

### borg specific entries (lines 1-4)

If you need help with these options, then you should consult the borg
documentation or search my blog at
[https://mytechiethoughts.com](https://mytechiethoughts.com) for borg. This is
especially true if you want to understand why an SSH key and passphrase are
preferred and why just a passphrase on it's own presents problems automating
borg backups.

### additional files/directories to backup

This points to a plain-text file listing additional files and directories you'd
like borg to include in the backup.  The sample file, *'xtraLocations.borg'*
contains the most likely files you'd want to include assuming you're using a
standard setup like I outline in my blog.

The following would include all files in the home folder for users *'foo'* and
*'bar'* and any conf files in *'/etc/someProgram'*:

```Bash
/home/foo/
/home/bar/
/etc/someProgram/*.conf
```

*You can leave this line blank* to tell borg to only backup your Mailcow data,
configuration and the SQL dump.  However, this is pretty unusual since you would
not be including any server configuration files, reverse-proxy configurations,
etc. If you omit this line, the script will log a warning to remind you of this
unusual situation.

### exclusion patterns

This points to a plain-text file containing borg-specific patterns describing
what files you'd like borg to ignore during the backup.  To specify exclusions,
create a text file in any location you want and specify exclusions patterns, one
per line.  Then update line 6 in your borg details file with the path to your
new exclusion file.

You need to run *'borg help patterns'* for help on how to specify exclusion
patterns since the format is not always standard BASH format and only sometimes
uses standard regex.

If you leave this line blank, the script will note it is not processing any
exclusions and will proceed with backing up all files specified.

### prune timeframe options

Here you can let borg prune know how you want to manage your backup history.
Consult the borg documentation and then copy the relevant options directly into
this line including any spaces, etc.  The example file contains the following as
a staring point:

```Ini
--keep-within=7d --keep-daily=30 --keep-weekly=12 --keep-monthly=-1
```

This would tell borg prune to keep ALL backups made for any reason within the
last 7 days, keep 30 days worth of daily backups, 12 weeks of end-of-week
backups and then an infinite amount of end-of-month backups.

### borg remote location

If you're using rsync.net, then just have this say *'borg1'*.  If you are using
another provider, you'll have to reference their locally installed copy of borg
relative to your home directory.  You can also leave this blank if your provider
does not run borg locally but your backups/restores will be slower.

### Examples

Repo in directory *'MailcowBackup'*, all fields including pointers to additional
files to backup, exclusion patterns and a remote borg path.  Prune: keep all
backups made in the last 14 days.

```Ini
/var/borgbackup
/var/borgbackup/SSHprivate.key
myuser@usw-s001.rsync.net:MailcowBackup/
myPaSsWoRd
/root/scripts/xtraLocations.borg
/root/scripts/excludeLocations.borg
--keep-within=14d
borg1
```

Repo in directory *'myBackup'*, no exclusions, keep 14 days end-of-day, 52 weeks
end-of-week

```Ini
/var/borgbackup
/root/keys/rsyncPrivate.key
myuser@usw-s001.rsync.net:myBackup/
PaSsWoRd
/var/borgbackup/include.list

--keep-daily=14 --keep-weekly=52
borg1
```

Repo in directory *'backup'*, no extra file locations, no exclusions, no remote
borg installation. Keep last 30 backups.

```Ini
/root/.borg
/root/.borg/private.key
username@server.tld:backup/
pAsSw0rD


--keep-within=30d

```

**Notice that the blank lines are very important!**

## 503 functionality

This script includes an entire section dedicated to copying an html file to act
as an error 503 notification page.  Error 503 is by definition "service
temporarily unavailable" which is exactly the case for your Mailcow server
during a backup since the mail-flow containers have been disabled.

The script copies whatever file is defined by the *'-5'* parameter (or the
default located at *'scriptpath/503.html'*) to whatever path is defined as the
'webroot' by the *'-w'* parameter.  This means that if you omit the *'-w'*
parameter, the script will necessarily skip this entire process and just issue a
warning to let you know about it.

### Conditional forwarding by your webserver

The script copying the file to the webroot is the easy part.  Your webserver has
to look for the presence of that file and generate a 503 error in order for the
magic to happen.  To do that, you have to include an instruction to that effect
in your default server definition and/or your Mailcow virtual server definition
file depending on your setup.

#### NGINX

You can copy the following code into the relevant server definition(s) on an
NGINX server:

```Perl
server {
    ...
    if (-f /usr/share/nginx/html/503.html) {
        return 503;
    }
...
    error_page 503 @backup
    location @backup {
        root /usr/share/nginx/html;
        rewrite ^(.*)$ /503.html break;
    }
}
```

This tells NGINX that if it finds the file *'503.html'* at the path
*'/usr/share/nginx/html'* (webroot on reverse proxy) then return an error code
503.  Upon encountering a 503 error, rewrite any url to *'domain.tld/503.html'*
and thus, display the custom 503 error page.  On the other hand, if it can't
find 503.html at the path specified (i.e. the script has deleted it because the
backup is completed), then go about business as usual.

#### Apache

I don't use apache for anything, ever... so I'm not sure how exactly you'd do
this but I think you'd have to use something like:

```Perl
RewriteEngine On
RewriteCond %{ENV:REDIRECT_STATUS} !=503
RewriteCond "/var/www/503.html" -f
RewriteRule ^ - [R=503,L]
...
ErrorDocument 503 /503.html
...
```

Let me know if that works and I'll update this document accordingly.  Like I
said, I don't use Apache so I can't really test it very easily.

#### Disabling 503 functionality altogether

If you don't want to use the 503 functionality for whatever reason and don't
want your log file junked up with warnings about it, then find the section of
the script file that starts with *'--- Begin 503 section ---'* and either
comment all the lines (put a *'#'* at the beginning of each line) or delete all
the lines until you get to *'--- End 503 section ---'*.

## Scheduling: Cron

After running this script at least once manually to test your settings, you
should schedule it to run automatically so things stay backed up.  This is
easiest with a simple cron job.

1. Open root's crontab:

    ```Bash
    sudo crontab -e
    ```

2. Add your script command line and set the time. I'm assuming your script is
   located at *'/root/scripts'*, all files are at their default locations and
   you want to run your backup at 1:07am daily.

    ```Bash
    7 1 * * * /root/scripts/backup.sh -l /var/log/backup.log -w /usr/share/nginx/html > /dev/null 2>&1
    ```

    The last part redirects all output to 'null' and forwards any errors to
    'null' also.  You don't need output because the script creates a wonderfully
    detailed log file that you can review :-)
3. Save the file and exit.
4. Confirm by listing the root user's crontab:

    ```Bash
    sudo crontab -l
    ```

## The log file

The script creates a very detailed log file of all major operations along with
any errors and warnings.  Everything is timestamped so you can see how long
things take and when any errors took place.  The script includes debugging
notes such as where temp files are located, where it's looking for data, whether
it created/moved/copied files, etc.  All major operations are tagged *'-- [INFO]
message here --'*.  Similarly, warnings are tagged *'-- [WARNING] message here
(code: xxxx) --'* and errors are tagged *'-- [ERROR] message here (code: xxx)
--'*.  Successful operations generate a *'-- [SUCCESS] message here --'* stamp.

Sections of the script are all colour-coded to make viewing it easier.  This
means you should use something like *'cat backup.log | more'* or *'tail -n
numberOfLines backup.log'* to view the file since the ansi colour codes
would make it difficult to read in nano or vi.

This tagging makes it easy for you to set up a log screening program to make
keeping an eye on your backup results easier.  If you plan on using Logwatch
(highly recommended, great program!) then I've done the work for you...

### Using Logwatch

Log-group, conf and service files are included so that you can easily setup
Logwatch to monitor the script's log file and report at your desired detail
level as follows:

    1. 0: Summary of total successes, warnings & errors only
    2. 1-4: Actual success, error & warning messages
    3. 5: Same as above, but includes info messages
    4. 6+: Dumps entire raw log file including debugging messages

A detailed breakdown of the files and all options are included in a separate
readme in the *'/etc/logwatch'* folder of this git archive.

If you don't really care how it works, you can just copy the files from this
archive to your *'/etc/logwatch'* directory.  The directory structure is correct
for a default Logwatch install on Debian/Ubuntu.  You will have to update the
log-group file to reflect the path to your script's log file.

### Remember to rotate your logs

The log file generated by this script is fairly detailed so it can grow quite
large over time.  This is especially true if you are using verbose output from
borg for any troubleshooting or for compliance/auditing.  I've included a sample
commented *logrotate config file* in this git archive at *'/etc/logrotate.d'*
which you can modify and drop into that same directory on your Debian/Ubuntu
system.  If you are using another log rotating solution, then please remember to
configure it so that your log files don't get overwhelmingly large should you
need to parse them if something goes wrong with your backups.

## Final notes

I think that's everything. If I've forgotten to document something, please let
me know. I know this readme is long but, I hate how much stuff for linux and
open-source programs/scripts in general are so poorly documented especially for
newbies and I didn't want to make that same mistake.

I don't script too often and I'm a horrible programmer, so if you see anything
that can be/should be improved, please let me know or submit your changes!  I
love learning new ways of doing things and getting feedback, so suggestions and
comments are more than welcome.

If this has helped you out, then please visit my blog at
[https://mytechiethoughts.com](https://mytechiethoughts.com) where I solve
problems like this all the time on a shoe-string or zero budget.  Thanks!