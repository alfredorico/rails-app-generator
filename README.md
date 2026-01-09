# Rails App Generator

A powerful bash script that generates production-ready Rails API + React projects with Docker, PostgreSQL, and automatic configuration.

## Features

✨ **Automated Rails Generation** - No manual post-installation steps required
🐳 **Docker-First** - Complete Docker setup for development and production
⚛️ **Optional React Frontend** - Vite-powered React with TypeScript or JavaScript
🔧 **Auto-Configuration** - Database and CORS automatically configured
🚀 **Production-Ready** - Includes best practices and optimized Dockerfiles
🔒 **Platform-Aware** - Proper file permissions on Linux, macOS, and WSL2

## Quick Start

```bash
# Generate Rails API only
./rails-app-generator.sh myapp

# Generate Rails API + React TypeScript frontend
./rails-app-generator.sh myapp --react-ts

# Generate Rails API + React JavaScript frontend
./rails-app-generator.sh myapp --react-js

# Custom versions
./rails-app-generator.sh myapp --ruby-version 3.3 --node-version 20 --rails-version 8.0
```

After generation, just:

```bash
cd myapp
make setup
make up
```

Your app is now running! 🎉

## Requirements

- **Docker** and **Docker Compose** installed and running
- **Node.js** and **npm** (only if using React frontend)
- **Linux**, **macOS**, or **WSL2** (Windows native not supported)

## Usage

### Basic Syntax

```bash
./rails-app-generator.sh <project-name> [options]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--ruby-version <version>` | Ruby version | 3.4 |
| `--node-version <version>` | Node.js version | 22 |
| `--postgres-version <version>` | PostgreSQL version | 15 |
| `--rails-version <version>` | Rails version | 8.1 |
| `--react-ts` | Include React frontend with TypeScript | - |
| `--react-js` | Include React frontend with JavaScript | - |
| `-h, --help` | Show help message | - |

### Examples

```bash
# Simple Rails API
./rails-app-generator.sh blog-api

# Full-stack with React TypeScript
./rails-app-generator.sh ecommerce --react-ts

# Custom Ruby and Rails versions
./rails-app-generator.sh legacy-app --ruby-version 3.2 --rails-version 7.1

# Full customization
./rails-app-generator.sh startup-mvp \
  --react-ts \
  --ruby-version 3.3 \
  --node-version 20 \
  --postgres-version 16 \
  --rails-version 8.0
```

## What Gets Generated

### Project Structure

**Rails API Only:**
```
myapp/
├── myapp-api/              # Rails API application
│   ├── app/
│   ├── config/
│   ├── db/
│   ├── Dockerfile.dev      # Development container
│   ├── entrypoint.sh       # Container entrypoint
│   └── ...
├── docker-compose.yml      # Docker services
└── makefile               # Developer shortcuts
```

**Rails API + React:**
```
myapp/
├── myapp-api/              # Rails API application
├── myapp-web-react/        # React frontend application
│   ├── src/
│   ├── public/
│   ├── Dockerfile.dev      # Development container
│   ├── Dockerfile          # Production container
│   ├── nginx.conf          # Production server config
│   └── ...
├── docker-compose.yml      # Docker services
└── makefile               # Developer shortcuts
```

### Automatic Configuration

The generator automatically:

1. **Generates Rails app** using standalone Docker (no image build required first)
2. **Configures database.yml** with proper PostgreSQL settings:
   - Development and test use explicit database names
   - Production uses DATABASE_URL pattern
   - Environment-based configuration (DB_HOST, DB_USERNAME, DB_PASSWORD)
3. **Sets up CORS** (when React is selected):
   - Uncomments rack-cors gem in Gemfile
   - Configures CORS middleware for localhost:5173
   - Ready for API consumption from frontend
4. **Creates Dockerfile.dev** optimized for development with hot-reloading
5. **Creates production Dockerfile** with multi-stage builds (React only)
6. **Initializes git repository** with meaningful first commit

## Generated Project Usage

### Initial Setup

After generating your project:

```bash
cd myapp
make setup    # Build images, install dependencies, create databases
make up       # Start all services
```

### Available Make Commands

| Command | Description |
|---------|-------------|
| `make setup` | Initial project setup (build + dependencies + db create) |
| `make up` | Start all services |
| `make down` | Stop all services |
| `make restart` | Restart all services |
| `make console` | Open Rails console |
| `make shell` | Open bash shell in API container |
| `make migrate` | Run database migrations |
| `make test` | Run Rails tests |
| `make rspec` | Run RSpec tests (if installed) |
| `make pg` | Open PostgreSQL console |
| `make rails <cmd>` | Run any Rails command |
| `make bundle <cmd>` | Run any Bundler command |
| `make npm <cmd>` | Run any npm command (React only) |

### Service URLs

- **API**: http://localhost:3000
- **Frontend**: http://localhost:5173 (React only)
- **Database**: localhost:5432

## Technical Details

### Docker Strategy

**Development:**
- Volume mounts for hot-reloading
- Separate volumes for gems (`bundle`) and node modules (`node_packages`)
- PostgreSQL with persistent data volume
- All services communicate via Docker network

**Production (React):**
- Multi-stage build (build → nginx)
- Optimized asset compilation
- Nginx serves static files and proxies API requests

### Database Configuration

The generated `database.yml`:

```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  host: <%= ENV.fetch("DB_HOST") { "db" } %>
  username: <%= ENV.fetch("DB_USERNAME") { "postgres" } %>
  password: <%= ENV.fetch("DB_PASSWORD") { "postgres" } %>

development:
  <<: *default
  database: myapp_development

test:
  <<: *default
  database: myapp_test

production:
  <<: *default
  url: <%= ENV["DATABASE_URL"] %>
```

This approach:
- ✅ Works seamlessly with Docker Compose
- ✅ Compatible with `rails db:create` and `rails db:migrate`
- ✅ Production-ready with DATABASE_URL pattern
- ✅ No manual configuration needed

### CORS Configuration

When React is selected, CORS is automatically configured:

**Gemfile:**
```ruby
gem "rack-cors"  # Automatically uncommented
```

**config/initializers/cors.rb:**
```ruby
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins 'http://localhost:5173'
    resource '*',
      headers: :any,
      expose: ['access-token', 'expiry', 'token-type', 'Authorization'],
      methods: [:get, :patch, :put, :delete, :post, :options, :show]
  end
end
```

### File Permissions

The script handles file permissions correctly across platforms:

- **Linux/macOS**: Uses `-u $(id -u):$(id -g)` to ensure generated files match host user
- **WSL2**: Same as Linux
- **Windows native**: Not supported (use WSL2 instead)

## Troubleshooting

### Docker daemon not running

```
[ERROR] Docker daemon is not running. Please start Docker Desktop.
```

**Solution:** Start Docker Desktop and ensure it's fully running before executing the script.

### Permission issues

If you encounter permission errors accessing generated files:

```bash
# On Linux/macOS, the script should handle this automatically
# If issues persist, check file ownership
ls -la myapp-api
```

### Database connection errors

If Rails can't connect to the database:

1. Ensure Docker Compose services are running: `docker-compose ps`
2. Check database environment variables in `docker-compose.yml`
3. Verify database exists: `make pg` then `\l` to list databases

### React frontend can't connect to API

Ensure CORS is properly configured:

1. Check that `rack-cors` gem is uncommented in Gemfile
2. Verify `config/initializers/cors.rb` exists and has correct origin
3. Restart API service: `docker-compose restart api`

## Contributing

Contributions are welcome! If you find bugs or have feature requests, please:

1. Check existing issues
2. Create a new issue with detailed description
3. Submit a pull request (if applicable)

## Changelog

### v2.0.0 (2026-01-09)
- **Fixed:** Database configuration for Rails db:create compatibility
- **Changed:** Removed `--skip-bundle` flag (Gemfile.lock now generated properly)
- **Changed:** Updated database.yml to use explicit DB_HOST/DB_USERNAME/DB_PASSWORD
- **Improved:** Better error messages and validation

### v1.0.0 (2026-01-09)
- **Added:** Automated Rails generation with standalone Docker run
- **Added:** Auto-configuration of database.yml with DATABASE_URL pattern
- **Added:** Auto-configuration of CORS when React is selected
- **Added:** Platform detection (Linux/macOS/WSL2 support)
- **Added:** Docker availability validation
- **Improved:** Simplified user workflow from 6 steps to 3 steps
- **Improved:** Better file permission handling
- Initial release

## License

This project is open source and available under the MIT License.

## Author

Alfredo E. Rico Moros

## Acknowledgments

Built with inspiration from modern Rails and React development practices, optimized for Docker-first workflows.
