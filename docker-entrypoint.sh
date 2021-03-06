#!/bin/bash
#set -e
set -x

# version_greater A B returns whether A > B
function version_greater() {
	[[ "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1" ]];
}

# return true if specified directory is empty
function directory_empty() {
    [ -n "$(find "$1"/ -prune -empty)" ]
}

function run_as() {
  if [[ $EUID -eq 0 ]]; then
    su - www-data -s /bin/bash -c "$1"
  else
    bash -c "$1"
  fi
}

installed_version="0.0.0~unknown"
if [ -f /var/www/html/version.php ]; then
    installed_version=$(php -r 'require "/var/www/html/version.php"; echo "$OC_VersionString";')
fi
image_version=$(php -r 'require "/usr/src/nextcloud/version.php"; echo "$OC_VersionString";')

if version_greater "$installed_version" "$image_version"; then
    echo "Can't start Nextcloud because the version of the data ($installed_version) is higher than the docker image version ($image_version) and downgrading is not supported. Are you sure you have pulled the newest image version?"
    exit 1
fi

if version_greater "$image_version" "$installed_version"; then
    if [ "$installed_version" != "0.0.0~unknown" ]; then
        run_as 'php /var/www/html/occ app:list' > /tmp/list_before
    fi
    if [[ $EUID -eq 0 ]]; then
      rsync_options=-a
    else
      rsync_options=-rlD
    fi
    rsync $rsync_options --delete --exclude /config/ --exclude /data/ --exclude /custom_apps/ --exclude /themes/ /usr/src/nextcloud/ /var/www/html/

    for dir in config data themes; do
        if [ ! -d /var/www/html/"$dir" ] || directory_empty /var/www/html/"$dir"; then
            cp -arT /usr/src/nextcloud/"$dir" /var/www/html/"$dir"
        fi
    done

    if [ ! -d /var/www/html/custom_apps ] && [ ! -f /var/www/html/config/apps.config.php ]; then
        cp -a /usr/src/nextcloud/config/apps.config.php /var/www/html/config/apps.config.php
    fi

    if [ ! -d /var/www/html/custom_apps ] || directory_empty /var/www/html/custom_apps; then
        cp -arT /usr/src/nextcloud/custom_apps /var/www/html/custom_apps
    fi

    if [ "$installed_version" != "0.0.0~unknown" ]; then
    	chmod -R 0770 /var/www/html/data
        run_as 'php /var/www/html/occ upgrade --no-app-disable'

        run_as 'php /var/www/html/occ app:list' > /tmp/list_after
        echo "The following apps have beed disabled:"
        diff <(sed -n "/Enabled:/,/Disabled:/p" /tmp/list_before) <(sed -n "/Enabled:/,/Disabled:/p" /tmp/list_after) | grep '<' | cut -d- -f2 | cut -d: -f1
        rm -f /tmp/list_before /tmp/list_after
    fi
fi

exec "$@"
