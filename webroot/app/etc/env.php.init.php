<?php
return [
    'cache' => [
        'frontend' => [
            'default' => [
                'frontend_options' => [
                    'write_control' => false
                ]
            ],
            'page_cache' => [
                'frontend_options' => [
                    'write_control' => false
                ]
            ]
        ]
    ],
    'system' => [
        'default' => [
            'design' => [
                'head' => [
                    'demonotice' => '1'
                ],
                'footer' => [
                    'absolute_footer' => '<script src="/livereload.js?port=443"></script>'
                ]
            ],
            'web' => [
                'secure' => [
                    'offloader_header' => 'X-Forwarded-Proto',
                    'use_in_frontend' => '1',
                    'use_in_adminhtml' => '1'
                ],
                'seo' => [
                    'use_rewrites' => '1'
                ],
                'url' => [
                    'use_store' => '0',
                    'redirect_to_base' => '1'
                ],
                'cookie' => [
                    'cookie_path' => null,
                    'cookie_httponly' => '1',
                    'cookie_restriction' => '0'
                ],
                'session' => [
                    'use_remote_addr' => '0',
                    'use_http_via' => '0',
                    'use_http_x_forwarded_for' => '0',
                    'use_http_user_agent' => '0',
                    'use_frontend_sid' => '1'
                ],
                'browser_capabilities' => [
                    'cookies' => '1',
                    'javascript' => '1',
                    'local_storage' => '0'
                ]
            ],
            'catalog' => [
                'frontend' => [
                    'list_allow_all' => '0',
                    'flat_catalog_category' => '0',
                    'flat_catalog_product' => '0'
                ],
                'search' => [
                    'engine' => 'elasticsearch7',
                    'enable_eav_indexer' => '1',
                    'elasticsearch7_server_hostname' => 'elasticsearch',
                    'elasticsearch7_server_port' => '9200',
                    'elasticsearch7_index_prefix' => 'magento2',
                    'elasticsearch7_enable_auth' => '0',
                    'elasticsearch7_server_timeout' => '15'
                ]
            ],
            'system' => [
                'full_page_cache' => [
                    'caching_application' => '2',
                    'ttl' => '604800'
                ]
            ],
            'dev' => [
                'front_end_development_workflow' => [
                    'type' => 'server_side_compilation'
                ],
                'template' => [
                    'allow_symlink' => '0',
                    'minify_html' => '0'
                ],
                'js' => [
                    'merge_files' => '0',
                    'enable_js_bundling' => '0',
                    'minify_files' => '0',
                    'translate_strategy' => 'dictionary',
                    'session_storage_logging' => '0',
                    'session_storage_key' => 'collected_errors'
                ],
                'css' => [
                    'merge_css_files' => '0',
                    'minify_files' => '0'
                ],
                'image' => [
                    'default_adapter' => 'GD2'
                ],
                'static' => [
                    'sign' => '0'
                ]
            ],
            'admin' => [
                'url' => [
                    'use_custom' => '0',
                    'use_custom_path' => '0'
                ],
                'security' => [
                    'use_form_key' => '1',
                    'use_case_sensitive_login' => '0',
                    'session_lifetime' => '7200',
                    'lockout_failures' => '6',
                    'lockout_threshold' => '30',
                    'password_lifetime' => '90',
                    'password_is_forced' => '1'
                ]
            ]
        ]
    ]
];
