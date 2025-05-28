#!/bin/bash
# install_lqpanel.sh - Cài đặt proxy + PHP8.4 + OPcache + Proxy Cache + menu lqpanel
# Dành cho Rocky 8

set -e

# Kiểm tra root
if [[ $EUID -ne 0 ]]; then
  echo "Chạy script bằng root hoặc sudo nhé."
  exit 1
fi

# Cập nhật hệ thống
echo "Cập nhật hệ thống..."
dnf update -y

echo "Cài đặt nginx, php 8.4, php-fpm, opcache..."
dnf module reset php -y
dnf module enable php:8.4 -y
dnf install -y nginx php php-fpm php-opcache curl unzip wget

# Bật opcache trong php.ini
PHP_INI=/etc/php.ini
if ! grep -q '^opcache.enable=1' $PHP_INI; then
  echo "opcache.enable=1" >> $PHP_INI
  echo "opcache.memory_consumption=128" >> $PHP_INI
  echo "opcache.interned_strings_buffer=8" >> $PHP_INI
  echo "opcache.max_accelerated_files=10000" >> $PHP_INI
  echo "opcache.revalidate_freq=2" >> $PHP_INI
fi

# Tạo thư mục cache proxy nginx
mkdir -p /var/cache/nginx/lqproxy_cache
chown -R nginx:nginx /var/cache/nginx/lqproxy_cache

# Thêm proxy_cache_path vào nginx.conf nếu chưa có
if ! grep -q 'proxy_cache_path /var/cache/nginx/lqproxy_cache' /etc/nginx/nginx.conf; then
  sed -i '1i\\
proxy_cache_path /var/cache/nginx/lqproxy_cache levels=1:2 keys_zone=lqproxy_cache:10m max_size=1g inactive=10m use_temp_path=off;\\
' /etc/nginx/nginx.conf
fi

# Khởi động và enable dịch vụ
systemctl enable --now nginx
systemctl enable --now php-fpm

# Tạo file menu lqpanel.sh (phần 2 sẽ gửi cho mày)
cat > /usr/local/bin/lqpanel.sh <<'EOF'
#!/bin/bash

create_proxy_config() {
  local domain=$1
  local backend_ip=$2
  local cache_enabled=$3
  local conf_file="/etc/nginx/conf.d/${domain}.conf"

  cat > $conf_file <<EOF
server {
  listen 80;
  server_name ${domain};

  location / {
    proxy_pass http://${backend_ip};
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
EOF

  if [[ "$cache_enabled" == "on" ]]; then
    cat >> $conf_file <<'CACHE_CONF'
    proxy_cache lqproxy_cache;
    proxy_cache_valid 200 5m;
    proxy_cache_methods GET HEAD;
    proxy_cache_bypass $http_cache_control;
CACHE_CONF
  fi

  cat >> $conf_file <<'EOF_END'
  }
}
EOF_END
}

lqpanel_menu() {
  while true; do
    clear
    echo "==== LQPanel quản lý proxy VPS Sing ===="
    echo "1) Tạo/Sửa domain proxy"
    echo "2) Xem trạng thái dịch vụ"
    echo "3) Bật cache proxy"
    echo "4) Tắt cache proxy"
    echo "5) Khởi động lại nginx"
    echo "6) Hiển thị thông tin máy chủ"
    echo "0) Thoát"
    echo -n "Chọn: "
    read -r choice

    case $choice in
      1)
        echo -n "Nhập domain: "
        read -r domain
        echo -n "Nhập IP backend (server Nga): "
        read -r ip
        cache_status="off"
        if grep -q "proxy_cache lqproxy_cache" "/etc/nginx/conf.d/${domain}.conf" 2>/dev/null; then
          cache_status="on"
        fi
        echo "Cache hiện tại: $cache_status"
        echo -n "Bật cache cho domain này? (y/n): "
        read -r yn
        if [[ "$yn" == "y" || "$yn" == "Y" ]]; then
          cache_enabled="on"
        else
          cache_enabled="off"
        fi
        create_proxy_config "$domain" "$ip" "$cache_enabled"
        nginx -t && systemctl reload nginx
        echo "Domain proxy đã được tạo/sửa với cache=$cache_enabled."
        read -n1 -r -p "Nhấn phím bất kỳ để tiếp tục..."
        ;;
      2)
        echo "Trạng thái nginx:"
        systemctl status nginx --no-pager
        echo "Trạng thái php-fpm:"
        systemctl status php-fpm --no-pager
        read -n1 -r -p "Nhấn phím bất kỳ để tiếp tục..."
        ;;
      3)
        echo -n "Nhập domain muốn bật cache: "
        read -r domain
        if [[ -f "/etc/nginx/conf.d/${domain}.conf" ]]; then
          sed -i '/proxy_cache lqproxy_cache/d' "/etc/nginx/conf.d/${domain}.conf"
          sed -i "/proxy_pass http:\/\/.*;/a \\    proxy_cache lqproxy_cache;\n    proxy_cache_valid 200 5m;\n    proxy_cache_methods GET HEAD;\n    proxy_cache_bypass \$http_cache_control;" "/etc/nginx/conf.d/${domain}.conf"
          nginx -t && systemctl reload nginx
          echo "Đã bật cache cho domain $domain."
        else
          echo "File config domain không tồn tại."
        fi
        read -n1 -r -p "Nhấn phím bất kỳ để tiếp tục..."
        ;;
      4)
        echo -n "Nhập domain muốn tắt cache: "
        read -r domain
        if [[ -f "/etc/nginx/conf.d/${domain}.conf" ]]; then
          sed -i '/proxy_cache lqproxy_cache/d' "/etc/nginx/conf.d/${domain}.conf"
          sed -i '/proxy_cache_valid/d' "/etc/nginx/conf.d/${domain}.conf"
          sed -i '/proxy_cache_methods/d' "/etc/nginx/conf.d/${domain}.conf"
          sed -i '/proxy_cache_bypass/d' "/etc/nginx/conf.d/${domain}.conf"
          nginx -t && systemctl reload nginx
          echo "Đã tắt cache cho domain $domain."
        else
          echo "File config domain không tồn tại."
        fi
        read -n1 -r -p "Nhấn phím bất kỳ để tiếp tục..."
        ;;
      5)
        systemctl restart nginx
        echo "Đã khởi động lại nginx."
        read -n1 -r -p "Nhấn phím bất kỳ để tiếp tục..."
        ;;
      6)
        echo "Thông tin máy chủ:"
        echo "IP VPS Sing:"
        ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print \$2}'
        echo "Tên máy:"
        hostname
        echo "Phiên bản nginx:"
        nginx -v
        echo "Phiên bản PHP:"
        php -v | head -n 1
        echo "Phiên bản hệ điều hành:"
        cat /etc/os-release | grep PRETTY_NAME
        read -n1 -r -p "Nhấn phím bất kỳ để tiếp tục..."
        ;;
      0)
        exit 0
        ;;
      *)
        echo "Lựa chọn không hợp lệ."
        sleep 1
        ;;
    esac
  done
}

lqpanel_menu
EOF

chmod +x /usr/local/bin/lqpanel.sh

echo "Tạo alias lqpanel cho tất cả user..."
if ! grep -q 'alias lqpanel=' /etc/profile; then
  echo "alias lqpanel='/usr/local/bin/lqpanel.sh'" >> /etc/profile
fi

echo "Cài đặt xong. Bạn chạy lệnh 'lqpanel' để quản lý."
