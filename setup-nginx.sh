#!/bin/bash

set -x

# Grab our libs
. "`dirname $0`/setup-lib.sh"

if [ -f $OURDIR/nginx-done ]; then
    exit 0
fi

logtstart "nginx"

maybe_install_packages nginx
# Handle case where nginx won't start because the default site (which is
# enabled!) needs port 80, and apache might be listening there.
#rm -f /etc/nginx/sites-available/default \
#    /etc/nginx/sites-enabled/default
if [ ! $? -eq 0 ]; then
    maybe_install_packages nginx
fi

$SUDO mkdir /var/www/profile-private
$SUDO chown www-data /var/www/profile-private
$SUDO mount -o bind,ro $WWWPRIV /var/www/profile-private/
echo $WWWPRIV /var/www/profile-private none defaults,bind 0 0 | $SUDO tee -a /etc/fstab
cat <<EOF | $SUDO tee /etc/nginx/sites-available/profile-private
server {
        include /etc/nginx/mime.types;
        types { text/plain log; }
        listen 7999 default_server;
        listen [::]:7999 default_server;
        root /var/www/profile-private;
        index index.html;
        server_name _;
        location / {
                 autoindex on;
        }
}
EOF
$SUDO ln -s /etc/nginx/sites-available/profile-private \
    /etc/nginx/sites-enabled/profile-private

$SUDO mkdir -p /local/profile-public
$SUDO chown $SWAPPER /local/profile-public
$SUDO mkdir /var/www/profile-public
$SUDO chown www-data /var/www/profile-public
$SUDO mount -o bind,ro $WWWPUB /var/www/profile-public/
echo $WWWPUB /var/www/profile-public none defaults,bind 0 0 | $SUDO tee -a /etc/fstab
cat <<EOF | $SUDO tee /etc/nginx/sites-available/profile-public
server {
        include /etc/nginx/mime.types;
        types { text/plain log; }
        listen 7998 default_server;
        listen [::]:7998 default_server;
        root /var/www/profile-public;
        index index.html;
        server_name _;
        location / {
                 autoindex on;
        }
}
EOF
$SUDO ln -s /etc/nginx/sites-available/profile-public \
    /etc/nginx/sites-enabled/profile-public
service_enable nginx
service_restart nginx

logtend "nginx"
touch $OURDIR/nginx-done
