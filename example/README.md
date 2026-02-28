# synthetic_api example

## Install
```bash
dart pub global activate synthetic_api_cli
```

## Usage

### Initialize a new project
```bash
synthetic-api init
```

### Start the mock server
```bash
synthetic-api dev --config synthetic-api.config.json --port 4010
```

### Validate your config
```bash
synthetic-api validate --config synthetic-api.config.json
```

### Expose via tunnel
```bash
synthetic-api tunnel --port 4010
```

## Example config

See the generated `synthetic-api.config.json` after running `init` for a full working example with routes, auth, pagination, and fixtures.