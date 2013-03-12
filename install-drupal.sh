#!/bin/bash

requirement_check() {
  HAS_GIT=`command -v git >/dev/null && echo "1" || echo "0"`
  HAS_JAVA=`command -v java >/dev/null && echo "1" || echo "0"`
  HAS_UUENCODE=`command -v uuencode >/dev/null && echo "1" || echo "0"`

  if [ "$HAS_GIT" = "0" ]; then
    echo "To keep track of changes we must use git. Please install it first."
    exit;
  fi

  if [ "$HAS_JAVA" = "0" ]; then
    echo "To run Solr, Java is a must have. Please install it."
    exit;
  fi

  if [ "$HAS_UUENCODE" = "0" ]; then
    echo "To generate passwords, uuencode is a must have. Please install the package sharutils to get it."
    exit;
  fi
}

# RUN THE CHECK
requirement_check

check_apachesolr_module() {
  APACHESOLR_VER=$(drush pm-info apachesolr | grep Version | awk -F: '{print $2}' | sed 's/\s//g')
  if [ "$APACHESOLR_VER" != "" ]; then
    VERSION_CHECK=$(drush ev "if (version_compare('$APACHESOLR_VER', '7.x-1.0-beta17', '>=')) { echo '1'; } else { echo '0'; }")
    if [ $VERSION_CHECK -eq 1 ]; then
      echo "apachesolr module $APACHESOLR_VER is as good or better than 7.x-1.0-beta17"
    elif [ "$(drush @sites solr-get-env-url --yes 2>&1 | grep 'could not be found')" = "" ]; then
      echo "The apachesolr module is only $APACHESOLR_VER, but has been patched, so we're good";
    else
      echo "Please upgrade apachesolr module from $APACHESOLR_VER to at least 7.x-1.0-beta17"
      exit 1;
    fi
  else
    echo 'Could not determine apachesolr module version. Is it installed?'
    exit 1
  fi
}

generate_password() {
  requirement_check
  head /dev/urandom | uuencode -m - | sed -n 2p | cut -c1-${1:-8};
}

# rawurlencode and decode functions ripped shamelessly from
# http://stackoverflow.com/a/10660730

rawurlencode() {
  local string="${1}"
  local strlen=${#string}
  local encoded=""

  for (( pos=0 ; pos<strlen ; pos++ )); do
     c=${string:$pos:1}
     case "$c" in
        [-_.~a-zA-Z0-9] ) o="${c}" ;;
        * )               printf -v o '%%%02x' "'$c"
     esac
     encoded+="${o}"
  done
  echo "${encoded}"    # You can either set a return variable (FASTER) 
  REPLY="${encoded}"   #+or echo the result (EASIER)... or both... :p
}

# Returns a string in which the sequences with percent (%) signs followed by
# two hex digits have been replaced with literal characters.
rawurldecode() {

  # This is perhaps a risky gambit, but since all escape characters must be
  # encoded, we can replace %NN with \xNN and pass the lot to printf -b, which
  # will decode hex for us

  printf -v REPLY '%b' "${1//%/\\x}" # You can either set a return variable (FASTER)
  echo "${REPLY}"  #+or echo the result (EASIER)... or both... :p
}


# Default values

DRUPAL_MAJOR=7
DRUPAL_MINOR=21
DRUPAL_VERSION=$DRUPAL_MAJOR'.'$DRUPAL_MINOR
SOLR_HOST='localhost'
SOLR_PORT='8983'
SOLR_VERSION=3.5
SOLR_LOCATION='/usr/local/solr-3.5.0'
SOLR_CORES_PATH='drupal/multicore'

CURRENT_DIR=`pwd`

echo -n "What is the webserver username used to run the site? [apache]: "
  read SERVER_USER
  if [ "$SERVER_USER" = "" ]; then
    SERVER_USER='apache'
  fi

echo -n "What is the webserver group used to run the site? [${SERVER_USER}]: "
  read SERVER_GROUP
  if [ "$SERVER_GROUP" = "" ]; then
    SERVER_GROUP=$SERVER_USER
  fi

echo -n "What is the drupal root for this site (Please use the entire path)? [${CURRENT_DIR}]: "
  read INSTALL_ROOT
  if [ "$INSTALL_ROOT" = "" ]; then
    INSTALL_ROOT=$CURRENT_DIR
  fi

cd $INSTALL_ROOT

DRUPAL_ROOT=`drush status --pipe 2>/dev/null | grep drupal_root | awk -F= '{print $2}'`
SOLR_MODULE_PATH=`drush pm-info apachesolr 2>/dev/null | grep Path | awk -F: '{print $2}' | sed 's/\s//g'`

if [ "$SOLR_MODULE_PATH" != "" ]; then
  check_apachesolr_module
fi

echo -n 'Please enter the username for the site database: '
  read DRUPAL_DB_USER

echo -n 'Please enter the password for the site database: '
  read DRUPAL_DB_PASS
DRUPAL_DB_PASS=$(rawurlencode ${DRUPAL_DB_PASS})

echo -n 'Please enter the hostname for the site database [localhost]: '
  read DRUPAL_DB_HOST
  if [ "$DRUPAL_DB_HOST" = "" ]; then
    DRUPAL_DB_HOST='localhost'
  fi

echo -n 'Please enter the current environment for the site [dev]: '
  read DEV_ENVIRONMENT
  if [ "$DEV_ENVIRONMENT" = "" ]; then
    DEV_ENVIRONMENT='dev'
  fi

echo -n 'What is the external url for the site (no www. prefix)? [example.com]: '
  read SITE_URL
  if [ "$SITE_URL" = "" ]; then
    SITE_URL='example.com'
  fi

echo -n 'What is the internal name for the site? [default]: '
  read INTERNAL_NAME
  if [ "$INTERNAL_NAME" = "" ]; then
    INTERNAL_NAME='default'
  fi

DRUPAL_DB_NAME=d"$DRUPAL_MAJOR"_"$INTERNAL_NAME"_"$DEV_ENVIRONMENT"
SITES_DIR=$INTERNAL_NAME
SOLR_CORE_NAME=d"$DRUPAL_MAJOR"-"$INTERNAL_NAME"

echo -n 'What is the external name of the site/project? [Site-Install]: '
  read DRUPAL_SITE_NAME
  if [ "$DRUPAL_SITE_NAME" = "" ]; then
    DRUPAL_SITE_NAME='Site-Install'
  fi

echo -n "What is the administrator (uid1) email for the site? [admin@${SITE_URL}]: "
  read DRUPAL_ADMIN_EMAIL
  if [ "$DRUPAL_ADMIN_EMAIL" = "" ]; then
    DRUPAL_ADMIN_EMAIL="admin@${SITE_URL}"
  fi

TEMP_GEN_PASSWORD=$(generate_password)
echo -n "What is the administrator (uid1) password for the site? [${TEMP_GEN_PASSWORD}]: "
  read DRUPAL_ADMIN_PASS
  if [ "$DRUPAL_ADMIN_PASS" = "" ]; then
    DRUPAL_ADMIN_PASS=${TEMP_GEN_PASSWORD}
  fi

echo -n "What is the site email (email used to send emails from the site)? [admin@${SITE_URL}]: "
  read DRUPAL_SITE_EMAIL
  if [ "$DRUPAL_SITE_EMAIL" = "" ]; then
    DRUPAL_SITE_EMAIL="admin@${SITE_URL}"
  fi

echo -n 'What site install profile should be used to install this site? [k4h_affiliate]: '
  read DRUPAL_INSTALL_PROFILE
  if [ "$DRUPAL_INSTALL_PROFILE" = "" ]; then
    DRUPAL_INSTALL_PROFILE='k4h_affiliate'
  fi

echo -n "What is the solr root path? [${SOLR_LOCATION}/${SOLR_CORES_PATH}]: "
  read SOLR_ROOT_PATH
  if [ "$SOLR_ROOT_PATH" = "" ]; then
    SOLR_ROOT_PATH=${SOLR_LOCATION}/${SOLR_CORES_PATH}
  fi

echo "\n******************************\nPlease confirm that all your answers above are correct."
echo -n "If they are, please type 'continue', or press Ctrl-C to cancel: "
  read CONFIRM_CONTINUE
  if [ "$CONFIRM_CONTINUE" != "continue" ]; then
    echo 'Alright, better luck next time. Exiting.'
    exit
  fi

drush site-install --root='${INSTALL_ROOT}' --db-url='mysql://${DRUPAL_DB_USER}:${DRUPAL_DB_PASS}@${DRUPAL_DB_HOST}:3306/${DRUPAL_DB_NAME}' --sites-subdir='${SITES_DIR}' --account-mail='${DRUPAL_ADMIN_EMAIL}' --account-pass='${DRUPAL_ADMIN_PASS}' --site-mail='${DRUPAL_SITE_EMAIL}' --site-name='${DRUPAL_SITE_NAME}' ${DRUPAL_INSTALL_PROFILE}

chown -R ${SERVER_USER}:${SERVER_GROUP} ${INSTALL_ROOT}/sites/${SITES_DIR}/files

cd ${INSTALL_ROOT}/sites/${SITES_DIR}

if [ "$SOLR_MODULE_PATH" = "" ]; then
  check_apachesolr_module
  SOLR_MODULE_PATH=`drush pm-info apachesolr 2>/dev/null | grep Path | awk -F: '{print $2}' | sed 's/\s//g'`
fi

cp -r ${SOLR_ROOT_PATH}/d${DRUPAL_MAJOR}-start ${SOLR_ROOT_PATH}/${SOLR_CORE_NAME}

SOLR_CONF_PATH="${INSTALL_ROOT}/${SOLR_MODULE_PATH}/solr-conf/solr-3.x"
SOLR_CORE_PATH="${SOLR_ROOT_PATH}/${SOLR_CORE_NAME}/conf"

timestamp=$(date +%s)

for file in `ls --color=never ${SOLR_CONF_PATH}`; do
  echo
  if [ -f ${SOLR_CORE_PATH}/$file ]; then
      echo "Backing up ${SOLR_CORE_PATH}/$file"
      mv ${SOLR_CORE_PATH}/$file{,.$timestamp.bak} || exit
  fi
  echo "Linking ${SOLR_CONF_PATH}/$file"
  ln -s $SOLR_CONF_PATH/$file ${SOLR_CORE_PATH}/
done

SOLR_ENV_URL="http://${SOLR_HOST}:${SOLR_PORT}/solr/${SOLR_CORE_NAME}"

echo "Setting Solr Environment URL to '${SOLR_ENV_URL}'"
drush solr-set-env-url "${SOLR_ENV_URL}"

echo "Please add '<core name=\"$SOLR_CORE_NAME\" instanceDir=\"$SOLR_CORE_NAME\" />'"
echo "to $SOLR_ROOT_PATH/solr.xml, and restart the solr service."
echo ''
echo 'Then make sure that there is a virtualhost entry for the site,'
echo ''
if [ "$INTERNAL_NAME" != "default" && ! grep "\$sites\['${SITE_URL}'\] = '${INTERNAL_NAME}';" ${INSTALL_ROOT}/sites/sites.php >/dev/null ]; then
  echo "and make sure that there is a sites.php entry referencing $INTERNAL_NAME:"
  echo "\$sites['${SITE_URL}'] = '${INTERNAL_NAME}';" | tee -a ${INSTALL_ROOT}/sites/sites.php
  echo ''
fi
echo 'and restart Apache, then we are done!'
echo ''
echo -n 'Would you like to add additional users now? (y/n): '
  read ADD_USERS
  if [ "$ADD_USERS" = "n" ]; then exit; fi

echo "Alright. We'll continue."

usernames=()
passwords=()
usermails=()

while true; do
echo -n 'Username: '
  read DRUPAL_USERNAME
  usernames+=("${DRUPAL_USERNAME}")
echo -n 'Password: '
  read DRUPAL_USERPASS
  passwords+=("${DRUPAL_USERPASS}")
echo -n 'Email: '
  read DRUPAL_USERMAIL
  usermails+=("${DRUPAL_USERMAIL}")
echo -n 'Add another? (y/n): '
  read CONTINUE
  if [[ ${CONTINUE} =~ ^[yY].* ]]; then echo "Alright. We'll continue."; else break; fi
done

cd ${INSTALL_ROOT}/sites/${SITES_DIR}

for i in "${!usernames[@]}"; do
   drush user-create "'${usernames[$i]}'" --password="'${passwords[$i]}'" --mail="'${usermails[$i]}'";
done
