# Using Logwatch to monitor the backup script

## quick start

Simply copy the contents of this folder to your logwatch configuration directory (*/etc/logwatch/* by default). The directory structure is already correct for a default Debian/Ubuntu logwatch installation. You **must** update the paths in */etc/logwatch/conf/logfiles/backup.conf* to point to your script's log file, but that's the only required change. Please consult [page 7.1.5](https://git.asifbacchus.app/asif/MailcowBackup/wiki/7.1.5-Testing) in the wiki for information on how to test logwatch using this new configuration.

## more information

Please consult [section 7.1](https://git.asifbacchus.app/asif/MailcowBackup/wiki/7.1-Using-logwatch) in the wiki for detailed information about each logwatch configuration file contained within this section of the git repo and how to customize them for your environment.

## final thoughts

I hope this helps you get your mailcow backup integrated with logwatch easily and quickly. If you have any suggestions/improvements, drop me a line in the issues section!
