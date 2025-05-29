#!/bin/bash
# install-lqpanel.sh
# Tao boi ChatGPT cho mày

set -e

## Cho apt/dpkg khac ket thuc neu co (Ubuntu) voi timeout 60s
if [[ -f /etc/debian_version ]]; then
  echo "Dang kiem tra tien trinh apt/dpkg..."
  TIMEOUT=60
  while [[ $TIMEOUT -gt 0 ]] && {
    fuser /var/lib/dpkg/lock >/dev/null 2>&1 ||
    fuser /var/lib/apt/lists/lock >/dev/null 2>&1 ||
    fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ;
  }; do
    echo "Tien trinh apt/dpkg dang chay, doi 5s ($TIMEOUT s con lai)"
    sleep 5
    TIMEOUT=$((TIMEOUT - 5))
  done
  if [[ $TIMEOUT -le 0 ]]; then
    echo "❌ Qua thoi gian cho (60s), tien trinh apt van bi lock. Vui long thu lai sau."
    exit 1
  fi
fi

## Check OS
OS="$(. /etc/os-release && echo "$ID")"
VERSION_ID="$(. /etc/os-release && echo "$VERSION_ID")"

if [[ "$OS" != "ubuntu" && "$OS" != "rocky" && "$OS" != "almalinux" ]]; then
  echo "Chi ho tro Ubuntu 22, Rocky Linux 8 va AlmaLinux 8"
  exit 1
fi

## Update system
if [[ "$OS" == "ubuntu" ]]; then
  export DEBIAN_FRONTEND=noninteractive
  apt update -yq && apt upgrade -yq && apt install -yq curl git sudo lsb-release net-tools unzip software-properties-common gnupg2 ca-certificates ufw
elif [[ "$OS" == "rocky" || "$OS" == "almalinux" ]]; then
  dnf update -y && dnf install -y epel-release && dnf install -y curl git sudo redhat-lsb-core net-tools unzip policycoreutils-python-utils firewalld gnupg
fi

## Create panel folder and modules
mkdir -p /opt/lqpanel/modules

## Install Nginx
if [[ "$OS" == "ubuntu" ]]; then
  curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" > /etc/apt/sources.list.d/nginx.list
  apt update -yq && apt install -yq nginx
else
  curl -o /etc/pki/rpm-gpg/nginx_signing.key https://nginx.org/keys/nginx_signing.key
  rpm --import /etc/pki/rpm-gpg/nginx_signing.key
  cat > /etc/yum.repos.d/nginx.repo <<EOF
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/nginx_signing.key
module_hotfixes=true
EOF
  dnf install -y nginx
fi
systemctl enable nginx && systemctl start nginx

## Install PHP
if [[ "$OS" == "ubuntu" ]]; then
  add-apt-repository ppa:ondrej/php -y && apt update -yq
  apt install -yq php7.4 php7.4-fpm php7.4-mysql php7.4-opcache \
                 php8.2 php8.2-fpm php8.2-mysql php8.2-opcache
else
  dnf install -y dnf-utils http://rpms.remirepo.net/enterprise/remi-release-8.rpm
  dnf module reset php -y
  dnf module enable php:remi-7.4 -y && dnf install -y php php-fpm php-mysqlnd php-opcache
  dnf module enable php:remi-8.2 -y && dnf install -y php82 php82-php-fpm php82-php-mysqlnd php82-php-opcache
fi

## Install MariaDB
if [[ "$OS" == "ubuntu" ]]; then
  apt install -yq mariadb-server mariadb-client
else
  curl -o /etc/pki/rpm-gpg/MariaDB-GPG-KEY https://downloads.mariadb.com/MariaDB/MariaDB-Server-GPG-KEY
  rpm --import /etc/pki/rpm-gpg/MariaDB-GPG-KEY
  cat > /etc/yum.repos.d/MariaDB.repo <<EOF
[mariadb]
name = MariaDB
baseurl = https://downloads.mariadb.com/MariaDB/mariadb-10.6/yum/rhel/\$releasever/\$basearch
gpgkey=file:///etc/pki/rpm-gpg/MariaDB-GPG-KEY
gpgcheck=1
enabled=1
EOF
  dnf install -y mariadb-server mariadb
fi
systemctl enable mariadb && systemctl start mariadb

## Install phpMyAdmin
wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz -O /tmp/phpmyadmin.tar.gz
mkdir -p /usr/share/phpmyadmin
rm -rf /usr/share/phpmyadmin/*
tar xzf /tmp/phpmyadmin.tar.gz --strip-components=1 -C /usr/share/phpmyadmin

## Install CSF
cd /usr/src && curl -s https://download.configserver.com/csf.tgz | tar -xz
cd csf && sh install.sh

## Tạo menu chính và alias
cat > /opt/lqpanel/lqpanel.sh << 'EOF'
#!/bin/bash

show_menu() {
  clear
  echo "========== LQPANEL =========="
  echo "1) Thong tin he thong VPS"
  echo "2) Quan ly Web (them/xoa domain + user)"
  echo "3) Quan ly Database (them/xoa DB)"
  echo "4) Cai dat web server (Nginx + PHP)"
  echo "5) Cai dat MariaDB + phpMyAdmin"
  echo "6) Chuyen doi PHP version"
  echo "7) Bat GZIP + Cache Headers"
  echo "8) Chan quoc gia truy cap"
  echo "9) Backup code & database"
  echo "10) Health Check + Don rac"
  echo "11) Cai CSF Firewall"
  echo "12) Phan quyen website"
  echo "0) Thoat"
  echo "=============================="
}

while true; do
  show_menu
  read -p "Lua chon: " opt
  case $opt in
    1) bash /opt/lqpanel/modules/system_info.sh;;
    2) bash /opt/lqpanel/modules/domain_manage.sh;;
    3) bash /opt/lqpanel/modules/db_manage.sh;;
    4) bash /opt/lqpanel/modules/install_nginx.sh && bash /opt/lqpanel/modules/install_php.sh;;
    5) bash /opt/lqpanel/modules/install_mariadb.sh && bash /opt/lqpanel/modules/install_phpmyadmin.sh;;
    6) bash /opt/lqpanel/modules/php_switch.sh;;
    7) bash /opt/lqpanel/modules/enable_gzip.sh;;
    8) bash /opt/lqpanel/modules/block_country.sh;;
    9) bash /opt/lqpanel/modules/backup.sh;;
    10) bash /opt/lqpanel/modules/healthcheck.sh;;
    11) bash /opt/lqpanel/modules/install_csf.sh;;
    12) bash /opt/lqpanel/modules/site_permission.sh;;
    0) exit;;
    *) echo "Lua chon khong hop le!"; read -p "Nhan Enter...";;
  esac
done
EOF

chmod +x /opt/lqpanel/lqpanel.sh
ln -sf /opt/lqpanel/lqpanel.sh /usr/bin/lqpanel

## Tạo placeholder cho modules
MODULE_LIST=(
  system_info domain_manage db_manage install_nginx install_php install_mariadb install_phpmyadmin
  php_switch enable_gzip block_country backup healthcheck install_csf site_permission
)
for mod in "${MODULE_LIST[@]}"; do
  echo -e "#!/bin/bash
echo [\$mod] chua duoc viet." > "/opt/lqpanel/modules/\$mod.sh"
  chmod +x "/opt/lqpanel/modules/$mod.sh"
done

## Thong bao hoan tat
clear
echo "===================================="
echo "Cai dat hoan tat!"
echo "Chay lenh 'lqpanel' de bat dau menu."
echo "===================================="
echo "VPS se tu dong khoi dong lai sau 5 giay..."
sleep 5
reboot
