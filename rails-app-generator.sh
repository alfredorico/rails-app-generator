#!/bin/bash

# Rails + React Dockerized Project Generator
# Generates a complete boilerplate for a Rails API + React frontend project
# with Docker, PostgreSQL, and common development tooling.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PROJECT_NAME=""
RUBY_VERSION="3.4"
NODE_VERSION="22"
POSTGRES_VERSION="15"
RAILS_VERSION="8.1"
REACT_TEMPLATE=""  # Empty means no React app

print_usage() {
    echo "Usage: $0 <project-name> [options]"
    echo ""
    echo "Options:"
    echo "  --ruby-version <version>     Ruby version (default: $RUBY_VERSION)"
    echo "  --node-version <version>     Node.js version (default: $NODE_VERSION)"
    echo "  --postgres-version <version> PostgreSQL version (default: $POSTGRES_VERSION)"
    echo "  --rails-version <version>    Rails version (default: $RAILS_VERSION)"
    echo "  --react-ts                   Include React frontend with TypeScript"
    echo "  --react-js                   Include React frontend with JavaScript"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 myapp --react-ts"
    echo "  $0 myapp --react-js --ruby-version 3.3 --node-version 20"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_usage
            exit 0
            ;;
        --ruby-version)
            RUBY_VERSION="$2"
            shift 2
            ;;
        --node-version)
            NODE_VERSION="$2"
            shift 2
            ;;
        --postgres-version)
            POSTGRES_VERSION="$2"
            shift 2
            ;;
        --rails-version)
            RAILS_VERSION="$2"
            shift 2
            ;;
        --react-ts)
            REACT_TEMPLATE="react-ts"
            shift
            ;;
        --react-js)
            REACT_TEMPLATE="react"
            shift
            ;;
        -*)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
        *)
            if [[ -z "$PROJECT_NAME" ]]; then
                PROJECT_NAME="$1"
            else
                log_error "Unexpected argument: $1"
                print_usage
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$PROJECT_NAME" ]]; then
    log_error "Project name is required"
    print_usage
    exit 1
fi

# Validate project name (alphanumeric, hyphens, underscores)
if [[ ! "$PROJECT_NAME" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
    log_error "Invalid project name. Use only letters, numbers, hyphens, and underscores. Must start with a letter."
    exit 1
fi

# ============================================================================
# Validation Functions
# ============================================================================

detect_platform() {
    case "$OSTYPE" in
        linux-gnu*)
            PLATFORM="linux"
            ;;
        darwin*)
            PLATFORM="macos"
            ;;
        msys*|cygwin*)
            log_error "Native Windows is not supported. Please use WSL2."
            log_error "Install WSL2: https://docs.microsoft.com/en-us/windows/wsl/install"
            exit 1
            ;;
        *)
            log_warn "Unknown platform: $OSTYPE. Script may not work correctly."
            PLATFORM="unknown"
            ;;
    esac
    log_info "Platform detected: $PLATFORM"
}

check_docker_available() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is required but not installed."
        log_error "Install: https://www.docker.com/products/docker-desktop"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker Desktop."
        exit 1
    fi
}

generate_rails_app() {
    log_info "Generating Rails ${RAILS_VERSION} application..."

    # Set user flag based on platform
    local DOCKER_USER_FLAG=""
    if [[ "$PLATFORM" == "linux" ]] || [[ "$PLATFORM" == "macos" ]]; then
        DOCKER_USER_FLAG="-u $(id -u):$(id -g)"
    fi

    # Generate Rails app
    if ! docker run --rm -it \
        -v "$(pwd)/${API_DIR}:/app" \
        -w /app \
        ${DOCKER_USER_FLAG} \
        ruby:${RUBY_VERSION} \
        bash -c "gem install --no-document rails -v '~> ${RAILS_VERSION}' && \
            rails new . --api --database=postgresql --skip-git --skip-test --skip-system-test --force"; then

        log_error "Rails generation failed!"
        log_error "Cleaning up ${API_DIR}..."
        rm -rf "${API_DIR}"
        exit 1
    fi

    # Remove Rails-generated .git if present
    rm -rf "${API_DIR}/.git" "${API_DIR}/.github"

    log_success "Rails application generated successfully"
}

configure_database_yml() {
    local db_yml="${API_DIR}/config/database.yml"

    log_info "Configuring database.yml to use DATABASE_URL..."

    # Backup original
    cp "$db_yml" "${db_yml}.backup"

    # Replace with our template
    cat > "$db_yml" << EOF
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  host: <%= ENV.fetch("DB_HOST") { "db" } %>
  username: <%= ENV.fetch("DB_USERNAME") { "postgres" } %>
  password: <%= ENV.fetch("DB_PASSWORD") { "postgres" } %>

development:
  <<: *default
  database: ${PROJECT_SNAKE}_development

test:
  <<: *default
  database: ${PROJECT_SNAKE}_test

production:
  <<: *default
  url: <%= ENV["DATABASE_URL"] %>
EOF

    log_success "Database configuration updated"
}

configure_cors() {
    log_info "Configuring CORS for React frontend..."

    local gemfile="${API_DIR}/Gemfile"
    local cors_initializer="${API_DIR}/config/initializers/cors.rb"

    # 1. Uncomment rack-cors gem (Rails API adds it commented by default)
    if grep -q "^# gem.*rack-cors" "$gemfile"; then
        sed -i.backup 's/^# gem.*rack-cors.*/gem "rack-cors"/' "$gemfile"
        log_info "Uncommented rack-cors gem in Gemfile"
    else
        # Fallback: add if not present
        sed -i.backup '/^gem "rails"/a gem "rack-cors"' "$gemfile"
        log_info "Added rack-cors gem to Gemfile"
    fi

    # 2. Replace cors.rb with your configuration
    cat > "$cors_initializer" << 'EOF'
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins 'http://localhost:5173'
    resource(
      '*',
      headers: :any,
      expose: ['access-token', 'expiry', 'token-type', 'Authorization'],
      methods: [:get, :patch, :put, :delete, :post, :options, :show]
    )
  end
end
EOF

    log_success "CORS configured for http://localhost:5173"
}

# Detect platform and check Docker availability
detect_platform
check_docker_available

# Check for npx if React is requested
if [[ -n "$REACT_TEMPLATE" ]]; then
    if ! command -v npx &> /dev/null; then
        log_error "npx is required to create React app but it's not installed."
        log_error "Please install Node.js and npm first."
        exit 1
    fi
fi

# Convert to snake_case for Rails conventions
PROJECT_SNAKE=$(echo "$PROJECT_NAME" | sed 's/-/_/g')
API_DIR="${PROJECT_NAME}-api"
WEB_DIR="${PROJECT_NAME}-web-react"

log_info "Creating project: $PROJECT_NAME"
log_info "Ruby: $RUBY_VERSION | Node: $NODE_VERSION | PostgreSQL: $POSTGRES_VERSION | Rails: $RAILS_VERSION"
if [[ -n "$REACT_TEMPLATE" ]]; then
    log_info "React template: $REACT_TEMPLATE"
fi

# Check if directory exists
if [[ -d "$PROJECT_NAME" ]]; then
    log_error "Directory '$PROJECT_NAME' already exists"
    exit 1
fi

# Create project directory
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"

log_info "Creating directory structure..."

# ============================================================================
# Create docker-compose.yml
# ============================================================================
log_info "Creating docker-compose.yml..."

if [[ -n "$REACT_TEMPLATE" ]]; then
    # Full docker-compose with frontend
    cat > docker-compose.yml << EOF
services:
  api: &app-base
    build:
      context: ./${API_DIR}
      dockerfile: Dockerfile.dev
    volumes:
      - ./${API_DIR}:/app
      - bundle:/bundle
    environment: &app-env
      DB_HOST: db
      DB_USERNAME: postgres
      DB_PASSWORD: postgres
      EDITOR: \${EDITOR:-nano}
    ports:
      - "3000:3000"
    stdin_open: true
    tty: true
    depends_on:
      - db

  frontend:
    build:
      context: ./${WEB_DIR}
      dockerfile: Dockerfile.dev
    volumes:
      - ./${WEB_DIR}:/app
      - node_packages:/app/node_modules
    ports:
      - "5173:5173"
    stdin_open: true
    tty: true

  db:
    image: postgres:${POSTGRES_VERSION}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"

volumes:
  postgres_data:
  bundle:
  node_packages:
EOF
else
    # API-only docker-compose
    cat > docker-compose.yml << EOF
services:
  api: &app-base
    build:
      context: ./${API_DIR}
      dockerfile: Dockerfile.dev
    volumes:
      - ./${API_DIR}:/app
      - bundle:/bundle
    environment: &app-env
      DB_HOST: db
      DB_USERNAME: postgres
      DB_PASSWORD: postgres
      EDITOR: \${EDITOR:-nano}
    ports:
      - "3000:3000"
    stdin_open: true
    tty: true
    depends_on:
      - db

  db:
    image: postgres:${POSTGRES_VERSION}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"

volumes:
  postgres_data:
  bundle:
EOF
fi

# ============================================================================
# Create Makefile
# ============================================================================
log_info "Creating Makefile..."

if [[ -n "$REACT_TEMPLATE" ]]; then
    # Full makefile with npm commands
    cat > makefile << 'EOF'
.PHONY: rails console test migrate setup

bundle:
	docker-compose run --rm api bundle $(filter-out $@,$(MAKECMDGOALS))

# Rails commands
rails:
	docker-compose run --rm api bin/rails $(filter-out $@,$(MAKECMDGOALS))

# Common shortcuts
console:
	docker-compose run --rm api bin/rails console

test:
	docker-compose run --rm api bin/rails test

migrate:
	docker-compose run --rm api bin/rails db:migrate

pg:
	docker-compose exec db psql -U postgres

shell:
	docker-compose run --rm api bash

# Project setup
setup:
	docker-compose build --no-cache
	docker-compose run --rm api bin/setup --skip-server
	docker-compose run --rm -e RAILS_ENV=test api bin/rails db:create

rspec:
	docker-compose run --rm api bundle exec rspec $(filter-out $@,$(MAKECMDGOALS))

up:
	docker-compose up

down:
	docker-compose down

restart:
	docker-compose restart

npm:
	docker-compose run --rm frontend npm $(filter-out $@,$(MAKECMDGOALS))

# Catch-all rule for arguments
%:
	@:
EOF
else
    # API-only makefile
    cat > makefile << 'EOF'
.PHONY: rails console test migrate setup

bundle:
	docker-compose run --rm api bundle $(filter-out $@,$(MAKECMDGOALS))

# Rails commands
rails:
	docker-compose run --rm api bin/rails $(filter-out $@,$(MAKECMDGOALS))

# Common shortcuts
console:
	docker-compose run --rm api bin/rails console

test:
	docker-compose run --rm api bin/rails test

migrate:
	docker-compose run --rm api bin/rails db:migrate

pg:
	docker-compose exec db psql -U postgres

shell:
	docker-compose run --rm api bash

# Project setup
setup:
	docker-compose build --no-cache
	docker-compose run --rm api bin/setup --skip-server
	docker-compose run --rm -e RAILS_ENV=test api bin/rails db:create

rspec:
	docker-compose run --rm api bundle exec rspec $(filter-out $@,$(MAKECMDGOALS))

up:
	docker-compose up

down:
	docker-compose down

restart:
	docker-compose restart

# Catch-all rule for arguments
%:
	@:
EOF
fi

# ============================================================================
# Create Rails API directory and files
# ============================================================================
log_info "Creating Rails API boilerplate..."

mkdir -p "${API_DIR}"

# Generate Rails application
generate_rails_app

# Configure database.yml
configure_database_yml

# Configure CORS if React is selected
if [[ -n "$REACT_TEMPLATE" ]]; then
    configure_cors
fi

# Dockerfile.dev for Rails
cat > "${API_DIR}/Dockerfile.dev" << EOF
# Dockerfile.dev
FROM ruby:${RUBY_VERSION}

RUN apt-get update -qq && apt-get install -y \\
  build-essential \\
  libpq-dev \\
  nano \\
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app

ENV BUNDLE_PATH=/bundle \\
    BUNDLE_JOBS=4 \\
    BUNDLE_RETRY=3 \\
    BUNDLE_APP_CONFIG="/bundle"

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

COPY entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0"]
EOF

# entrypoint.sh
cat > "${API_DIR}/entrypoint.sh" << 'EOF'
#!/bin/bash
set -e

# Remove a potentially pre-existing server.pid for Rails.
rm -f /app/tmp/pids/server.pid

# Then exec the container's main process (what's set as CMD in the Dockerfile).
exec "$@"
EOF
chmod +x "${API_DIR}/entrypoint.sh"

# Append to .dockerignore (Rails creates one, we add our entries)
cat >> "${API_DIR}/.dockerignore" << 'EOF'

# Additional Docker-specific ignores
.bundle
vendor/bundle
EOF

# ============================================================================
# Create React frontend using Vite (if requested)
# ============================================================================
if [[ -n "$REACT_TEMPLATE" ]]; then
    log_info "Creating React frontend with Vite (template: $REACT_TEMPLATE)..."

    # Use npx create-vite to generate the React app
    # --no-rolldown: skip experimental rolldown-vite prompt
    # --no-interactive: skip all interactive prompts
    npx create-vite@latest "${WEB_DIR}" --template "$REACT_TEMPLATE" --no-rolldown --no-interactive

    # Change into the frontend directory
    cd "${WEB_DIR}"

    # Run npm install to generate proper package-lock.json
    log_info "Installing npm dependencies..."
    npm install

    # Go back to project root
    cd ..

    # Determine file extension based on template
    if [[ "$REACT_TEMPLATE" == "react-ts" ]]; then
        CONFIG_EXT="ts"
    else
        CONFIG_EXT="js"
    fi

    # Update vite.config for Docker compatibility (host binding and polling)
    log_info "Updating vite.config for Docker compatibility..."
    cat > "${WEB_DIR}/vite.config.${CONFIG_EXT}" << EOF
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: 5173,
    watch: {
      usePolling: true,
    },
  },
})
EOF

    # Create Dockerfile.dev for React
    cat > "${WEB_DIR}/Dockerfile.dev" << EOF
# Dockerfile.dev
FROM node:${NODE_VERSION}-alpine

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

EXPOSE 5173

CMD ["npm", "run", "dev"]
EOF

    # Create .dockerignore
    cat > "${WEB_DIR}/.dockerignore" << 'EOF'
node_modules
dist
.git
.gitignore
EOF

    # Create nginx.conf for production
    cat > "${WEB_DIR}/nginx.conf" << 'EOF'
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api {
        proxy_pass http://api:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

    # Create Production Dockerfile for React
    cat > "${WEB_DIR}/Dockerfile" << EOF
# Build stage
FROM node:${NODE_VERSION}-alpine as build

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

# Production stage
FROM nginx:alpine

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
EOF
fi

# ============================================================================
# Create root .gitignore
# ============================================================================
cat > .gitignore << 'EOF'
# IDE
.idea/
.vscode/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Environment
.env
.env.local
.env.*.local
EOF

# ============================================================================
# Create README
# ============================================================================
if [[ -n "$REACT_TEMPLATE" ]]; then
    FRONTEND_TECH="Node.js ${NODE_VERSION}, React, Vite"
    FRONTEND_SECTION="
2. **Start the application**:

   \`\`\`bash
   make up
   \`\`\`
"
    FRONTEND_COMMANDS="| \`make npm <cmd>\` | Run any npm command |"
    FRONTEND_URL="- **Frontend**: http://localhost:5173"
    PROJECT_STRUCTURE="
\`\`\`
${PROJECT_NAME}/
├── ${API_DIR}/          # Rails API application
├── ${WEB_DIR}/          # React frontend application
├── docker-compose.yml   # Docker services configuration
└── makefile             # Development shortcuts
\`\`\`"
else
    FRONTEND_TECH=""
    FRONTEND_SECTION="
2. **Start the application**:

   \`\`\`bash
   make up
   \`\`\`
"
    FRONTEND_COMMANDS=""
    FRONTEND_URL=""
    PROJECT_STRUCTURE="
\`\`\`
${PROJECT_NAME}/
├── ${API_DIR}/          # Rails API application
├── docker-compose.yml   # Docker services configuration
└── makefile             # Development shortcuts
\`\`\`"
fi

cat > README.md << EOF
# ${PROJECT_NAME}

A dockerized full-stack application with Rails API backend${FRONTEND_TECH:+ and React frontend}.

## Tech Stack

- **Backend**: Ruby ${RUBY_VERSION}, Rails ${RAILS_VERSION} (API mode)
${FRONTEND_TECH:+- **Frontend**: ${FRONTEND_TECH}}
- **Database**: PostgreSQL ${POSTGRES_VERSION}
- **Containerization**: Docker & Docker Compose

## Getting Started

### Prerequisites

- Docker
- Docker Compose

### Initial Setup

1. **Run setup**:

   \`\`\`bash
   make setup
   \`\`\`

2. **Start the application**:

   \`\`\`bash
   make up
   \`\`\`

### Available Commands

| Command | Description |
|---------|-------------|
| \`make up\` | Start all services |
| \`make down\` | Stop all services |
| \`make restart\` | Restart all services |
| \`make console\` | Rails console |
| \`make shell\` | Bash shell in API container |
| \`make migrate\` | Run database migrations |
| \`make test\` | Run Rails tests |
| \`make rspec\` | Run RSpec tests |
| \`make pg\` | PostgreSQL console |
| \`make rails <cmd>\` | Run any Rails command |
| \`make bundle <cmd>\` | Run any Bundler command |
${FRONTEND_COMMANDS}

### URLs

- **API**: http://localhost:3000
${FRONTEND_URL}
- **Database**: localhost:5432

## Project Structure
${PROJECT_STRUCTURE}
EOF

# ============================================================================
# Initialize git repository
# ============================================================================
log_info "Initializing git repository..."

git init --quiet
git add .
git commit -m "init: scaffold Rails ${RAILS_VERSION} API${REACT_TEMPLATE:+ + React ($REACT_TEMPLATE)} project with Docker" --quiet

# ============================================================================
# Done!
# ============================================================================
echo ""
log_success "Project '${PROJECT_NAME}' created successfully!"
echo ""
log_info "Rails ${RAILS_VERSION} API generated and configured"
if [[ -n "$REACT_TEMPLATE" ]]; then
    log_info "React frontend configured with CORS support"
fi
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "  1. cd ${PROJECT_NAME}"
echo ""
echo "  2. Run setup:"
echo "     make setup"
echo ""
echo "  3. Start the application:"
echo "     make up"
echo ""
echo -e "${GREEN}Happy coding!${NC}"
