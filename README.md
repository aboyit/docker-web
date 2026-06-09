# Docker-Web

Stack Docker cho nhiều website PHP dùng chung Nginx, MariaDB, Redis và tách riêng theo version PHP-FPM.

## Thành phần chính

- Nginx `1.25-alpine`
- PHP-FPM `7.4`, `8.1`, `8.3`
- MariaDB `10.11`
- Redis `7.2-alpine`
- phpMyAdmin `5` qua profile riêng `admin`
- Opcache trên cả 3 bản PHP
- Ioncube cho PHP `7.4`, `8.1`, `8.3`
- Imagick, GD, Intl, MySQLi, PDO MySQL, BCMath, Zip
- Composer `2`
- WP-CLI
- Git, Unzip, Zip, MySQL Client

## Kiến trúc chạy thực tế

- Một container `nginx` đứng trước nhận request theo domain.
- Mỗi app có một `server_name` riêng và trỏ về đúng thư mục code trong `www`.
- Mỗi app được chuyển tiếp sang đúng container PHP-FPM theo version.
- MariaDB và Redis dùng chung cho toàn stack.
- phpMyAdmin không mở public mặc định, chỉ bật khi cần.

Luồng request:

```text
Domain -> Nginx -> appXX.conf.template -> phpXX:9000 -> code trong /var/www/html/appXX
```

Ví dụ hiện tại:

- `APP74_DOMAIN` -> `www/app74` -> `php74:9000`
- `APP81_DOMAIN` -> `www/app81` -> `php81:9000`
- `APP83_DOMAIN` -> `www/app83` -> `php83:9000`

## Cấu trúc thư mục

```text
docker-compose.yml
.env
.env.example

nginx/
	nginx.conf
	conf.d/
		app74.conf.template
		app81.conf.template
		app83.conf.template

php/
	7.4.Dockerfile
	8.1.Dockerfile
	8.3.Dockerfile
	custom-php.ini
	custom-fpm.conf

mariadb/
	my.cnf

www/
	app74/
	app81/
	app83/
```

## Docker Compose hiện tại

### Service `nginx`

- Publish cổng `80` và `443`
- Mount:
	- `./nginx/nginx.conf:/etc/nginx/nginx.conf:ro`
	- `./nginx/conf.d:/etc/nginx/templates:ro`
	- `./www:/var/www/html:ro`
- Dùng `envsubst` có sẵn của image Nginx để render các file `*.template`
- Nhận biến:
	- `APP74_DOMAIN`
	- `APP81_DOMAIN`
	- `APP83_DOMAIN`
- Chờ `php74`, `php81`, `php83` ở trạng thái `service_healthy`

### Service `php74`

- Build từ `php/7.4.Dockerfile`
- Base image: `php:7.4-fpm-bullseye`
- Extension chính:
	- `pdo`
	- `pdo_mysql`
	- `mysqli`
	- `gd`
	- `zip`
	- `intl`
	- `bcmath`
	- `opcache`
	- `redis-5.3.7`
	- `imagick`
- Ioncube loader `7.4`
- Có sẵn `composer` và `wp`
- Có sẵn `git`, `unzip`, `zip`, `mysql`
- Chờ `redis` ở trạng thái `service_healthy`
- Có healthcheck kiểm tra cổng FPM `9000`

### Service `php81`

- Build từ `php/8.1.Dockerfile`
- Base image: `php:8.1-fpm-bookworm`
- Extension chính:
	- `pdo`
	- `pdo_mysql`
	- `mysqli`
	- `gd`
	- `zip`
	- `intl`
	- `bcmath`
	- `opcache`
	- `redis`
	- `imagick`
- Ioncube loader `8.1`
- Có sẵn `composer` và `wp`
- Có sẵn `git`, `unzip`, `zip`, `mysql`
- Chờ `redis` ở trạng thái `service_healthy`
- Có healthcheck kiểm tra cổng FPM `9000`

### Service `php83`

- Build từ `php/8.3.Dockerfile`
- Base image: `php:8.3-fpm-bookworm`
- Extension chính:
	- `pdo`
	- `pdo_mysql`
	- `mysqli`
	- `gd`
	- `zip`
	- `intl`
	- `bcmath`
	- `opcache`
	- `redis`
	- `imagick`
- Ioncube loader `8.3`
- Có sẵn `composer` và `wp`
- Có sẵn `git`, `unzip`, `zip`, `mysql`
- Chờ `redis` ở trạng thái `service_healthy`
- Có healthcheck kiểm tra cổng FPM `9000`

### Service `mariadb`

- Image: `mariadb:10.11`
- Tune thêm qua `command` và `mariadb/my.cnf`
- Dùng volume ngoài:
	- `prod_secure_db_data:/var/lib/mysql`
- Có healthcheck bằng `mariadb-admin ping`

### Service `redis`

- Image: `redis:7.2-alpine`
- Bật AOF:
	- `redis-server --appendonly yes`
- Giới hạn bộ nhớ:
	- `--maxmemory 256mb`
	- `--maxmemory-policy allkeys-lru`
- Dùng volume:
	- `redis_data:/data`
- Có healthcheck bằng `redis-cli ping`

### Service `phpmyadmin`

- Image: `phpmyadmin/phpmyadmin:5`
- Chỉ chạy khi bật profile `admin`
- Bind cục bộ:
	- `127.0.0.1:8888:80`
- Chờ `mariadb` ở trạng thái `service_healthy`

## File `.env`

File `.env` được dùng để:

- truyền thông tin database vào `mariadb`
- truyền domain vào container `nginx` để render template

Mẫu hiện tại:

```env
MYSQL_ROOT_PASSWORD=change_this_root_password
MYSQL_DATABASE=prod_main_db
MYSQL_USER=prod_web_user
MYSQL_PASSWORD=change_this_app_password
APP74_DOMAIN=app74.example.com
APP81_DOMAIN=app81.example.com
APP83_DOMAIN=app83.example.com
```

Lưu ý:

- Mỗi máy có thể có `.env` riêng.
- Không cần chia `dev`, `staging`, `prod` nếu chỉ muốn mỗi máy tự có domain riêng.
- Không nên đưa `.env` thật vào Git.
- Nên commit `.env.example` làm mẫu.

## Nginx template và map domain

Các file trong `nginx/conf.d` là template, ví dụ `app81.conf.template`:

- `server_name ${APP81_DOMAIN};`
- `root /var/www/html/app81;`
- `fastcgi_pass php81:9000;`

Nghĩa là khi `APP81_DOMAIN=hunix-lms.com` thì domain đó sẽ vào:

- thư mục code `www/app81`
- container `php81`

Nếu domain không match server block mong muốn, Nginx sẽ rơi về server block đầu tiên. Vì vậy domain phải được đặt đúng trong `.env` và `nginx` phải được recreate lại sau khi sửa `.env`.

## File cấu hình runtime

### `php/custom-php.ini`

- `memory_limit=512M`
- `upload_max_filesize=128M`
- `post_max_size=128M`
- `max_execution_time=300`
- `date.timezone=Asia/Ho_Chi_MinH`
- `opcache.validate_timestamps=0`
- bật JIT:
	- `opcache.jit=tracing`
	- `opcache.jit_buffer_size=128M`

### `php/custom-fpm.conf`

- `listen = 9000`
- `pm = dynamic`
- `pm.max_children = 50`
- `pm.start_servers = 10`
- `pm.min_spare_servers = 5`
- `pm.max_spare_servers = 20`
- `pm.max_requests = 1000`
- `request_terminate_timeout = 300`
- `slowlog = /var/log/php-fpm/www-slow.log`

### `mariadb/my.cnf`

Đã tune sẵn cho:

- `max_connections = 300`
- `max_allowed_packet = 128M`
- `skip-name-resolve = 1`
- `table_open_cache = 4000`
- `tmp_table_size = 128M`
- `max_heap_table_size = 128M`
- `innodb_buffer_pool_size = 1G`
- `innodb_log_file_size = 256M`
- `innodb_flush_log_at_trx_commit = 2`
- `innodb_flush_method = O_DIRECT`
- `innodb_io_capacity = 2000`

## Cài đặt trên server

Khuyên dùng thư mục `/srv` để chứa source chạy thực tế trên server.

Ví dụ tạo thư mục project:

```bash
mkdir -p /srv/web-host
cd /srv/web-host
```

Kéo project về server:

```bash
git clone <git_repo_url> .
```

Hoặc nếu đã có repo rồi:

```bash
cd /srv/web-host
git pull origin main
```

Tạo file môi trường từ file mẫu:

```bash
cp .env.example .env
```

Sau đó sửa `.env` theo đúng máy đang chạy:

- `MYSQL_ROOT_PASSWORD`
- `MYSQL_DATABASE`
- `MYSQL_USER`
- `MYSQL_PASSWORD`
- `APP74_DOMAIN`
- `APP81_DOMAIN`
- `APP83_DOMAIN`

Nếu project có app WordPress hoặc app PHP cần cài vendor bằng Composer thì chạy trong container PHP tương ứng sau khi stack đã lên:

```bash
docker compose exec php81 sh -lc "cd /var/www/html/app81 && composer install"
```

Nếu là WordPress có thể dùng thêm WP-CLI:

```bash
docker compose exec php81 sh -lc "cd /var/www/html/app81 && wp --allow-root core version"
```

## Khởi động stack

Tạo volume MariaDB ngoài trước:

```bash
docker volume create prod_secure_db_data
```

Lên toàn bộ stack:

```bash
docker compose up -d
```

Lên riêng `nginx` sau khi sửa domain trong `.env`:

```bash
docker compose up -d nginx
```

Lên phpMyAdmin khi cần:

```bash
docker compose --profile admin up -d phpmyadmin
```

## Khi nào cần `build`

Chỉ sửa `docker-compose.yml`, `.env`, `nginx.conf`, file template, `custom-php.ini`, `custom-fpm.conf`, `mariadb/my.cnf`:

```bash
docker compose up -d
```

Sửa Dockerfile PHP:

```bash
docker compose build php74 php81 php83
docker compose up -d php74 php81 php83 nginx
```

## Composer và WP-CLI

Trong cả `php74`, `php81`, `php83` đều có sẵn:

- `composer`
- `wp`
- `git`
- `unzip`
- `zip`
- `mysql`

Ví dụ dùng trong container PHP 8.1:

```bash
docker compose exec php81 composer --version
docker compose exec php81 wp --info --allow-root
```

Ví dụ chạy trong thư mục app WordPress:

```bash
docker compose exec php81 sh -lc "cd /var/www/html/app81 && composer install"
docker compose exec php81 sh -lc "cd /var/www/html/app81 && wp core version --allow-root"
```

## Import và export database

Project có sẵn 2 script ở root:

- `import.sh`: chọn file `.sql` hoặc `.sql.gz` rồi import vào database chọn lúc chạy
- `export.sh`: chọn database rồi export ra file `.sql` hoặc `.sql.gz`

Log sẽ được ghi vào thư mục `logs`.
File export mặc định được lưu trong thư mục `backups`.

Chay import:

```bash
sh import.sh
```

Hoac truyen san file dump:

```bash
sh import.sh /root/web-host/backup/lms.sql
```

Chay export:

```bash
sh export.sh
```

## Deploy code

Code không copy vào container. Code nằm trên host và được mount vào container qua:

```yaml
- ./www:/var/www/html
```

Nghĩa là:

- `www/app74` là code app PHP 7.4
- `www/app81` là code app PHP 8.1
- `www/app83` là code app PHP 8.3

Deploy đơn giản:

```bash
cd /root/web-host/www/app81
git pull origin main
cd /root/web-host
docker compose up -d nginx php81
```

## Chạy domain nội bộ trong mạng LAN hoặc máy local

Nếu VM Ubuntu có IP nội bộ, ví dụ `192.168.32.128`, có thể dùng file `hosts` trên máy Windows:

```text
192.168.32.128 hunix-lms.com
```

Sau đó đặt trong `.env`:

```env
APP81_DOMAIN=hunix-lms.com
```

Rồi apply lại:

```bash
docker compose up -d nginx
```

## Lệnh kiểm tra nhanh

Xem trạng thái container:

```bash
docker compose ps
```

Xem log nginx:

```bash
docker compose logs --tail=100 nginx
```

Xem log PHP 8.1:

```bash
docker compose logs --tail=100 php81
```

Test domain đúng server block nào ngay trên server:

```bash
curl -I -H "Host: hunix-lms.com" http://127.0.0.1
```

Kiểm tra cổng web trên host:

```bash
ss -tulpn | grep :80
ss -tulpn | grep :443
```

## Lưu ý vận hành

- `docker compose up -d nginx` không có nghĩa là xóa cài lại. Nó chỉ dựng hoặc recreate service cần thiết ở chế độ nền.
- `restart nginx` chỉ tắt bật lại container hiện có, không áp config mới từ `.env` hoặc compose.
- `depends_on: condition: service_healthy` nghĩa là service phụ thuộc phải `healthy` trước khi service hiện tại được start trong lúc `docker compose up`.
- `prod_secure_db_data` là external volume, phải tồn tại trước khi stack chạy.
- phpMyAdmin chỉ nên bật khi cần vì đây là công cụ quản trị nhạy cảm.
- Redis `7.2` hiện tại vẫn phù hợp với stack PHP này, đặc biệt là PHP `7.4` đang dùng `phpredis 5.3.7`.
