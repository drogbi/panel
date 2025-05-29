#!/bin/bash
# install-lqpanel-pro.sh
# Ban nhe, chia nho tung buoc, debug de, toi uu cho Ubuntu/Rocky/AlmaLinux

set -e
exec > >(tee /var/log/lqpanel-install.log) 2>&1

## Kiem tra OS
OS="$(. /etc/os-release && echo "$ID")"
VERSION_ID="$(. /etc/os-release && echo "$VERSION_ID")"

if [[ "$OS" != "ubuntu" && "$OS" != "rocky" && "$OS" != "almalinux" ]]; then
  echo "Chi ho tro Ubuntu 22, Rocky 8, AlmaLinux 8"
  exit 1
fi

## Chuan bi
echo "[+] Update he thong..."
if [[ "$OS" == "ubuntu" ]]; then
  export DEBIAN_FRONTEND=noninteractive
  apt update -y && apt install -y curl git sudo lsb-release net-tools unzip software-properties-common gnupg2 ca-certificates ufw
elif [[ "$OS" == "rocky" || "$OS" == "almalinux" ]]; then
  dnf update -y && dnf install -y epel-release && dnf install -y curl git sudo redhat-lsb-core net-tools unzip policycoreutils-python-utils firewalld gnupg
fi

## Cai Nginx
echo "[+] Cai Nginx..."
if [[ "$OS" == "ubuntu" ]]; then
  curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" > /etc/apt/sources.list.d/nginx.list
  apt update -y && apt install -y nginx
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

## Cai PHP
echo "[+] Cai PHP..."
if [[ "$OS" == "ubuntu" ]]; then
  add-apt-repository ppa:ondrej/php -y && apt update -y
  apt install -y php8.2 php8.2-fpm php8.2-mysql php8.2-opcache
else
  dnf install -y dnf-utils http://rpms.remirepo.net/enterprise/remi-release-8.rpm
  dnf module reset php -y
  dnf module enable php:remi-8.2 -y && dnf install -y php82 php82-php-fpm php82-php-mysqlnd php82-php-opcache
fi
systemctl enable php*-fpm && systemctl start php*-fpm

## Cai MariaDB
echo "[+] Cai MariaDB..."
if [[ "$OS" == "ubuntu" ]]; then
  apt install -y mariadb-server mariadb-client
else
  dnf install -y mariadb-server mariadb
fi
systemctl enable mariadb && systemctl start mariadb

## Cai phpMyAdmin
echo "[+] Cai phpMyAdmin..."
wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz -O /tmp/phpmyadmin.tar.gz
mkdir -p /usr/share/phpmyadmin && rm -rf /usr/share/phpmyadmin/*
tar xzf /tmp/phpmyadmin.tar.gz --strip-components=1 -C /usr/share/phpmyadmin

## Tao menu don gian
mkdir -p /opt/lqpanel
cat > /opt/lqpanel/lqpanel.sh << 'EOF'
#!/bin/bash

show_menu() {
  clear
  echo "===== LQPANEL DON GIAN ====="
  echo "1) Thong tin VPS"
  echo "2) Quan ly Web (them/xoa domain)"
  echo "3) Quan ly Database"
  echo "4) Backup Code + DB"
  echo "5) Cai dat Nginx + PHP"
  echo "6) Cai dat MariaDB + phpMyAdmin"
  echo "7) Chuyen doi PHP version"
  echo "8) Bat GZIP + Cache Headers"
  echo "9) Chan quoc gia truy cap"
  echo "10) Health Check + Don rac"
  echo "11) Cai CSF Firewall"
  echo "12) Phan quyen website"
  echo "0) Thoat"
  echo "============================="
}

while true; do
  show_menu
  read -p "Lua chon: " opt
  case $opt in
    1) bash /opt/lqpanel/modules/system_info.sh;;
    2) bash /opt/lqpanel/modules/domain_manage.sh;;
    3) bash /opt/lqpanel/modules/db_manage.sh;;
    4) bash /opt/lqpanel/modules/backup.sh;;
    5) bash /opt/lqpanel/modules/install_nginx.sh && bash /opt/lqpanel/modules/install_php.sh;;
    6) bash /opt/lqpanel/modules/install_mariadb.sh && bash /opt/lqpanel/modules/install_phpmyadmin.sh;;
    7) bash /opt/lqpanel/modules/php_switch.sh;;
    8) bash /opt/lqpanel/modules/enable_gzip.sh;;
    9) bash /opt/lqpanel/modules/block_country.sh;;
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

## Tao module placeholder
mkdir -p /opt/lqpanel/modules
for mod in system_info domain_manage db_manage backup install_nginx install_php install_mariadb install_phpmyadmin php_switch enable_gzip block_country healthcheck install_csf site_permission
  echo -e "#!/bin/bash
echo '[${mod}] chua co noi dung.'" > "/opt/lqpanel/modules/${mod}.sh"
  chmod +x "/opt/lqpanel/modules/${mod}.sh"
done

## Thong bao hoan tat
clear
echo "===================================="
echo "Cai dat LqPanel (ban nhe) hoan tat!"
echo "- Da tao menu: go 'lqpanel' de mo"
echo "- Log tai: /var/log/lqpanel-install.log"
echo "===================================="
echo "Muon reboot VPS de hoan tat? (y/n)"
read -r reboot_ans
if [[ "$reboot_ans" == "y" || "$reboot_ans" == "Y" ]]; then
  echo "Dang reboot..."
  sleep 3
  reboot
fi
