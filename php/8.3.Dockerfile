FROM php:8.3-fpm-bookworm

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

RUN apt-get update && apt-get install -y \
    pkg-config libpng-dev libjpeg-dev libfreetype6-dev zip libzip-dev libicu-dev curl wget libmagickwand-dev git --no-install-recommends \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install pdo pdo_mysql mysqli gd zip intl bcmath opcache

RUN pecl install redis && docker-php-ext-enable redis

RUN git clone https://github.com/Imagick/imagick.git --depth 1 /tmp/imagick \
    && cd /tmp/imagick \
    && phpize \
    && ./configure \
    && make \
    && make install \
    && docker-php-ext-enable imagick \
    && rm -rf /tmp/imagick

RUN mkdir -p /var/log/php-fpm \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz -o ioncube.tar.gz \
    && tar -xzvf ioncube.tar.gz \
    && mv ioncube/ioncube_loader_lin_8.3.so $(php-config --extension-dir) \
    && rm -rf ioncube.tar.gz ioncube \
    && echo "zend_extension=ioncube_loader_lin_8.3.so" > /usr/local/etc/php/conf.d/00-ioncube.ini

RUN curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp

WORKDIR /var/www/html