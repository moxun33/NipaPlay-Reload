# 列出文件目录

## OpenAPI Specification

```yaml
openapi: 3.0.1
info:
  title: ''
  description: ''
  version: 1.0.0
paths:
  /api/fs/list:
    post:
      summary: 列出文件目录
      deprecated: false
      description: ''
      tags:
        - fs
        - alist Copy/fs
      parameters:
        - name: Authorization
          in: header
          description: ''
          required: true
          example: '{{alist_token}}'
          schema:
            type: string
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                path:
                  type: string
                  title: 路径
                password:
                  type: string
                  title: 密码
                page:
                  type: integer
                  title: 页数
                per_page:
                  type: integer
                  title: 每页数目
                refresh:
                  type: boolean
                  title: 是否强制刷新
              x-apifox-orders:
                - path
                - password
                - page
                - per_page
                - refresh
            example:
              path: /t
              password: ''
              page: 1
              per_page: 0
              refresh: false
      responses:
        '200':
          description: ''
          content:
            application/json:
              schema:
                type: object
                properties:
                  code:
                    type: integer
                    title: 状态码
                  message:
                    type: string
                    title: 信息
                  data:
                    type: object
                    properties:
                      content:
                        type: array
                        items:
                          type: object
                          properties:
                            name:
                              type: string
                              title: 文件名
                            size:
                              type: integer
                              title: 大小
                            is_dir:
                              type: boolean
                              title: 是否是文件夹
                            modified:
                              type: string
                              title: 修改时间
                            created:
                              type: string
                              title: 创建时间
                            sign:
                              type: string
                              title: 签名
                            thumb:
                              type: string
                              title: 缩略图
                            type:
                              type: integer
                              title: 类型
                            hashinfo:
                              type: string
                            hash_info:
                              type: 'null'
                          x-apifox-orders:
                            - name
                            - size
                            - is_dir
                            - modified
                            - sign
                            - thumb
                            - type
                            - created
                            - hashinfo
                            - hash_info
                          required:
                            - name
                            - size
                            - is_dir
                            - modified
                            - sign
                            - thumb
                            - type
                        title: 内容
                      total:
                        type: integer
                        title: 总数
                      readme:
                        type: string
                        title: 说明
                      header:
                        type: string
                      write:
                        type: boolean
                        title: 是否可写入
                      provider:
                        type: string
                    required:
                      - content
                      - total
                      - readme
                      - header
                      - write
                      - provider
                    x-apifox-orders:
                      - content
                      - total
                      - readme
                      - write
                      - provider
                      - header
                required:
                  - code
                  - message
                  - data
                x-apifox-orders:
                  - code
                  - message
                  - data
              example:
                code: 200
                message: success
                data:
                  content:
                    - name: Alist V3.md
                      size: 1592
                      is_dir: false
                      modified: '2024-05-17T13:47:55.4174917+08:00'
                      created: '2024-05-17T13:47:47.5725906+08:00'
                      sign: ''
                      thumb: ''
                      type: 4
                      hashinfo: 'null'
                      hash_info: null
                  total: 1
                  readme: ''
                  header: ''
                  write: true
                  provider: Local
          headers: {}
          x-apifox-name: 成功
      security: []
      x-apifox-folder: fs
      x-apifox-status: released
      x-run-in-apifox: https://app.apifox.com/web/project/3653728/apis/api-128101246-run
components:
  schemas: {}
  securitySchemes: {}
servers:
  - url: http://test-cn.your-api-server.com
    description: 测试环境
  - url: http://prod-cn.your-api-server.com
    description: 正式环境
security: []

```

# 获取某个文件/目录信息

## OpenAPI Specification

```yaml
openapi: 3.0.1
info:
  title: ''
  description: ''
  version: 1.0.0
paths:
  /api/fs/get:
    post:
      summary: 获取某个文件/目录信息
      deprecated: false
      description: ''
      tags:
        - fs
        - alist Copy/fs
      parameters:
        - name: Authorization
          in: header
          description: ''
          required: true
          example: '{{alist_token}}'
          schema:
            type: string
      requestBody:
        content:
          application/json:
            schema:
              type: object
              properties:
                path:
                  type: string
                  title: 路径
                password:
                  type: string
                  title: 密码
                page:
                  type: integer
                per_page:
                  type: integer
                refresh:
                  type: boolean
                  title: 强制 刷新
              required:
                - path
                - password
              x-apifox-orders:
                - path
                - password
                - page
                - per_page
                - refresh
            example:
              path: /t
              password: ''
              page: 1
              per_page: 0
              refresh: false
      responses:
        '200':
          description: ''
          content:
            application/json:
              schema:
                type: object
                properties:
                  code:
                    type: integer
                    title: 状态码
                  message:
                    type: string
                    title: 信息
                  data:
                    type: object
                    properties:
                      name:
                        type: string
                        title: 文件名
                      size:
                        type: integer
                        title: 大小
                      is_dir:
                        type: boolean
                        title: 是否是文件夹
                      modified:
                        type: string
                        title: 修改时间
                      created:
                        type: string
                        title: 创建时间
                      sign:
                        type: string
                        title: 签名
                      thumb:
                        type: string
                        title: 缩略图
                      type:
                        type: integer
                        title: 类型
                      hashinfo:
                        type: string
                      hash_info:
                        type: 'null'
                      raw_url:
                        type: string
                        title: 原始url
                      readme:
                        type: string
                        title: 说明
                      header:
                        type: string
                      provider:
                        type: string
                      related:
                        type: 'null'
                    required:
                      - name
                      - size
                      - is_dir
                      - modified
                      - created
                      - sign
                      - thumb
                      - type
                      - hashinfo
                      - hash_info
                      - raw_url
                      - readme
                      - header
                      - provider
                      - related
                    x-apifox-orders:
                      - name
                      - size
                      - is_dir
                      - modified
                      - sign
                      - thumb
                      - type
                      - raw_url
                      - readme
                      - provider
                      - related
                      - created
                      - hashinfo
                      - hash_info
                      - header
                required:
                  - code
                  - message
                  - data
                x-apifox-orders:
                  - code
                  - message
                  - data
              example:
                code: 200
                message: success
                data:
                  name: Alist V3.md
                  size: 2618
                  is_dir: false
                  modified: '2024-05-17T16:05:36.4651534+08:00'
                  created: '2024-05-17T16:05:29.2001008+08:00'
                  sign: ''
                  thumb: ''
                  type: 4
                  hashinfo: 'null'
                  hash_info: null
                  raw_url: http://127.0.0.1:5244/p/local/Alist%20V3.md
                  readme: ''
                  header: ''
                  provider: Local
                  related: null
          headers: {}
          x-apifox-name: 成功
      security: []
      x-apifox-folder: fs
      x-apifox-status: released
      x-run-in-apifox: https://app.apifox.com/web/project/3653728/apis/api-128101247-run
components:
  schemas: {}
  securitySchemes: {}
servers:
  - url: http://test-cn.your-api-server.com
    description: 测试环境
  - url: http://prod-cn.your-api-server.com
    description: 正式环境
security: []

```