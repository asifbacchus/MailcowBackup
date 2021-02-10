# Mailcow Backup Using borgbackup <!-- omit in toc -->

This script automates backing up your Mailcow installation using borgbackup and a remote ssh-capable storage system.  I suggest using rsync.net since they
have great speeds and a special pricing structure for borgbackup/attic users ([details here](https://www.rsync.net/products/attic.html)).

This script automates the following tasks:

- Optionally copies a 503 error page to your webserver so users know when your server is unavailable due to backups being performed. The 503 file is removed
  when the backup is completed so users can login again
- Dumps the Mailcow mySQL database and adds it to the backup
- Handles stopping and re-starting mail-flow containers (postfix and dovecot) so everything is in a consistent state during the backup
- Allows you to specify additional files you want backed up
- Allows you to specify files/directories to exclude from your backups
- Runs 'borg prune' to make sure you are trimming old backups on your schedule
- Creates a clear, easy to parse log file so you can keep an eye on your backups and any errors/warnings

## Contents <!-- omit in toc -->

- [quick start](#quick-start)
- [configuration file](#configuration-file)
- [running the script](#running-the-script)
- [scheduling your backup via cron](#scheduling-your-backup-via-cron)
- [final notes](#final-notes)

## quick start

Clone this repo or download a release file into a directory of your choosing. For all examples in this document, I will assume you will run the script from */scripts/backup*. Make sure the script file is executable and you protect the *.details* file since it contains things like your repo password:

```bash
# run commands as root
sudo -s

# find somewhere to clone the repo
cd /usr/local/src

# clone the repo from my server (best choice)
git clone https://git.asifbacchus.app/asif/MailcowBackup.git
# or clone from github
git clone https://github.com/asifbacchus/MailcowBackup.git

# make a home for your backup script
mkdir -p /scripts/backup
cd /scripts/backup

# copy files from cloned repo to this new home
cp /usr/local/src/MailcowBackup/backup/* ./

# make script executable and protect your .details file
chmod +x backup.sh
chmod 600 backup.details
```

## configuration file

You will need to let the script know how to access your remote repo along with any passwords/keyfiles needed to encrypt data. This is all handled via the plain-text 'configuration details' file. By default, this file is named *backup.details*. The file itself is fully commented so setting it up should not be difficult. If you need more information, consult [page 4.0](https://git.asifbacchus.app/asif/MailcowBackup/wiki/4.0-Configuration-details-file) in the wiki.

## running the script

After setting up the *.details* file correctly and assuming you are running a default set up of mailcow according to the documentation, you just have to run the script and it will find everything on it's own. In particular, the defaults are set as follows:

- mailcow.conf is located at */opt/mailcow-dockerized/mailcow.conf*
- docker-compose file is located at */opt/mailcow-dockerized/docker-compose.yml*
- the log file will be saved in the same directory as the script with the same name as the script but with the extension *.log*

To get a list of all configuration options with defaults:

```bash
./backup.sh --help
```

To run with defaults:

```bash
./backup.sh
```

To run with a custom log file name and location:

```bash
./backup.sh --log /var/log/mailcow_backup.log
```

To copy a 503 error page to your webroot:

```bash
# assuming default NGINX webroot (/usr/share/nginx/html)
./backup.sh -5
# custom webroot
./backup.sh -5 -w /var/www/
```

Common usage: custom log file and copy 503 to custom webroot

```bash
./backup.sh -l /var/log/mailcow_backup.log -5 -w /var/www/
```

Non-default mailcow location (example: */var/mailcow*):

```bash
./backup.sh --docker-compose /var/mailcow/docker-compose.yml --mailcow-config /var/mailcow/mailcow.conf
```

For more configuration options, see [page 3.0](https://git.asifbacchus.app/asif/MailcowBackup/wiki/3.0-Script-parameters) in the wiki and [page 4.4](https://git.asifbacchus.app/asif/MailcowBackup/wiki/4.4-Configuration-examples) for some configuration examples. Consult [section 7](https://git.asifbacchus.app/asif/MailcowBackup/wiki/7.0-Logs) of the wiki for information about the log file and how to integrate it with logwatch.

## scheduling your backup via cron

Edit your root user's crontab and add an entry like this which would run the script using defaults at 1:07am daily:

```ini
7 1 * * * /scripts/backup/backup.sh -l /var/log/mailcow_backup.log > /dev/null 2>&1
```

## restoring backups

Starting with version 3.0, a *restore.sh* file has been included to semi-automate restoring your backups to a clean mailcow instance. There are a few steps required and they are better explained in the wiki than would be possible in a short write-up like this. Please check out the [restore process overview](https://git.asifbacchus.app/asif/MailcowBackup/wiki/8.0-Restore-overview) for more information.

## final notes

I think that's everything. For detailed information, please review the [wiki](https://git.asifbacchus.app/asif/MailcowBackup/wiki/_pages). If I've forgotten to document something there, please let me know. I know the wiki is long but, I hate how much stuff for Linux and open-source programs/scripts in general are so poorly documented especially for newbies and I didn't want to make that same mistake.

I don't script too often and I'm a horrible programmer, so if you see anything that can be/should be improved, please let me know by filing an issue or submit your changes via a pull request!  I love learning new ways of doing things and getting feedback, so suggestions and comments are more than welcome.

If this has helped you out, then please visit my blog at [https://mytechiethoughts.com](https://mytechiethoughts.com) where I solve problems like this all the time on a shoe-string or zero budget. Thanks!
