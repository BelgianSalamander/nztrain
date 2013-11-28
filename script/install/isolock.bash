#!/usr/bin/env bash

# run this script as root
source `dirname $0`/../install.cfg

isolockuser=isolock
srclocation=/usr/local/src
cd $srclocation
if [ -d "isolock" ]; then
  cd isolock
  done=true
  git pull | grep -q -v 'Already up-to-date.' && done=false
  if $done; then
    exit
  fi
else
  git clone https://github.com/ronalchn/isolock.git && cd isolock || exit 1
fi

if ! id -u $isolockuser >/dev/null 2>&1; then
  useradd -r isolock
fi

make && chown $isolockuser bin/isolock && chgrp $APP_USER bin/isolock && chmod 6750 bin/isolock || {
  echo "Failure to setup isolock permissions - aborting"
  cd ..
  rm -r $srclocation/isolock
  exit 1
}

ln -sf $srclocation/isolock/bin/isolock /usr/local/bin
