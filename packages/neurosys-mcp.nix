{ lib, fetchPypi, python3Packages }:

let
  mcp-sdk = python3Packages.buildPythonPackage rec {
    pname = "mcp";
    version = "1.26.0";
    pyproject = true;
    src = fetchPypi {
      inherit pname version;
      hash = "sha256-224u9JHuzBoNk3EadvKN7C4FmZ+Tr9SHldocETcULGY=";
    };
    build-system = [
      python3Packages.hatchling
      python3Packages."uv-dynamic-versioning"
    ];
    dependencies = [
      python3Packages.anyio python3Packages.httpx python3Packages."httpx-sse"
      python3Packages.jsonschema python3Packages.pydantic python3Packages."pydantic-settings"
      python3Packages.pyjwt python3Packages.python-multipart python3Packages."sse-starlette"
      python3Packages.starlette python3Packages."typing-extensions" python3Packages."typing-inspection"
      python3Packages.uvicorn python3Packages.cryptography
    ];
    pythonImportsCheck = [ "mcp" ];
    doCheck = false;
  };

  fastmcp = python3Packages.buildPythonPackage rec {
    pname = "fastmcp";
    version = "2.12.4";
    pyproject = true;
    src = fetchPypi {
      inherit pname version;
      hash = "sha256-tV/olTcDjxnQ9EdlRPnKWsFxAz9hgRzI8SvercvqUBY=";
    };
    build-system = [
      python3Packages.hatchling
      python3Packages."uv-dynamic-versioning"
    ];
    dependencies = [
      python3Packages.authlib python3Packages.cyclopts python3Packages.exceptiongroup
      python3Packages.httpx python3Packages.openapi-core python3Packages."openapi-pydantic"
      python3Packages.pydantic python3Packages.pyperclip python3Packages.python-dotenv
      python3Packages.rich python3Packages."email-validator" mcp-sdk
    ];
    pythonImportsCheck = [ "fastmcp" ];
    doCheck = false;
  };
in
python3Packages.buildPythonApplication {
  pname = "neurosys-mcp";
  version = "0.3.0";
  pyproject = true;
  src = ../src/neurosys-mcp;
  build-system = [ python3Packages.setuptools python3Packages.wheel ];
  dependencies = [
    fastmcp
    python3Packages.httpx
    python3Packages.orgparse
    python3Packages.google-auth
    python3Packages.requests
  ];
  pythonImportsCheck = [ "server" "auth" "logseq" "google_auth" "gmail" "calendar_tools" ];
  meta = with lib; {
    description = "FastMCP server exposing Home Assistant, Matrix, Logseq, Gmail, and Calendar tools for neurosys";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "neurosys-mcp";
  };
}
