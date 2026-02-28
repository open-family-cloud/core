<?php
/**
 * Open Family Cloud — Nextcloud カスタム設定
 *
 * S3 Primary Storage と LDAP 認証の設定。
 * 環境変数は docker-compose.yml から注入されます。
 *
 * このファイルは setup.sh 実行時に .env の値で生成されます。
 * 手動で編集する場合は docker-compose.override.yml 側で
 * マウントを上書きしてください。
 */
$CONFIG = [

    // --- S3 Primary Storage ---
    'objectstore' => [
        'class' => '\\OC\\Files\\ObjectStore\\S3',
        'arguments' => [
            'bucket'     => getenv('S3_BUCKET_NEXTCLOUD'),
            'key'        => getenv('S3_ACCESS_KEY'),
            'secret'     => getenv('S3_SECRET_KEY'),
            'hostname'   => parse_url(getenv('S3_ENDPOINT'), PHP_URL_HOST),
            'port'       => 443,
            'use_ssl'    => true,
            'region'     => getenv('S3_REGION'),
            'use_path_style' => true,
            'autocreate' => true,
        ],
    ],

    // --- パフォーマンス ---
    'memcache.local'       => '\\OC\\Memcache\\APCu',
    'memcache.distributed' => '\\OC\\Memcache\\Redis',
    'memcache.locking'     => '\\OC\\Memcache\\Redis',
    'filelocking.enabled'  => true,

    // --- メール ---
    'mail_smtpmode' => 'smtp',
    'mail_smtphost' => 'mailserver',
    'mail_smtpport' => 25,

    // --- セキュリティ ---
    'overwriteprotocol' => 'https',
    'default_phone_region' => 'JP',

    // --- ログ ---
    'loglevel' => 2,  // WARN
    'log_type' => 'file',
];
