FROM php:8.3-apache
RUN apt-get update -y && apt upgrade -y && apt-get install -y curl openssl zip git unzip lsb-release apt-transport-https ca-certificates wget nano
# Install extensions
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libonig-dev \
    libicu-dev \
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev \
    libpng-dev \
    libjpeg-dev \
    libzip-dev \
    zlib1g-dev \
    libfreetype6-dev \
    pkg-config \
    zip unzip git
RUN docker-php-ext-configure gd --with-freetype --with-jpeg
RUN apt-get clean && rm -rf /var/lib/apt/lists/*
RUN docker-php-ext-install \
      bcmath \
      gd \
      intl \
      pdo_mysql \
      soap \
      xsl \
      zip \
      sockets \
      ftp
RUN pecl install xdebug && docker-php-ext-enable xdebug
# Config
RUN a2enmod rewrite
COPY configFiles/000-default.conf /etc/apache2/sites-available/000-default.conf
COPY configFiles/apache2.conf /etc/apache2/apache2.conf
COPY configFiles/php.ini /usr/local/etc/php/php.ini
#COPY configFiles/xdebug.ini /usr/local/etc/php/conf.d/xdebug.ini
ENV PHP_INI_FILE php.ini
# Install composer
RUN apt-get update -y && curl -sS https://getcomposer.org/installer | php -- --version=2.8.11 && mv composer.phar /usr/local/bin/composer
RUN chown -R --silent :www-data /var/www/ && chmod -R --silent 775 /var/www/
