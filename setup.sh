
set -euo pipefail

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[*]${RESET} $*"; }
success() { echo -e "${GREEN}[✔]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }

echo -e "\n${CYAN}=== Recon Automation — Environment Setup ===${RESET}\n"

# membuat folder yg dibutuhkan
info "Creating project directories..."
mkdir -p input output scripts logs
success "Directories created: input/ output/ scripts/ logs/"

# cek environment
if ! command -v go &>/dev/null; then
    warn "Go is not installed. Installing..."
    sudo apt update -qq && sudo apt install -y golang-go
fi
success "Go version: $(go version)"

# add go ke path
GOBIN="$(go env GOPATH)/bin"
if [[ ":$PATH:" != *":$GOBIN:"* ]]; then
    warn "Adding $GOBIN to PATH..."
    echo "export PATH=\$PATH:$GOBIN" >> ~/.bashrc
    export PATH="$PATH:$GOBIN"
    success "Added $GOBIN to PATH (restart terminal or run: source ~/.bashrc)"
else
    success "GOPATH/bin already in PATH"
fi

# install pdtm
if ! command -v pdtm &>/dev/null; then
    info "Installing pdtm..."
    go install -v github.com/projectdiscovery/pdtm/cmd/pdtm@latest
fi
success "pdtm: $(pdtm -version 2>&1 | head -1)"

# install subfinder
info "Installing subfinder via pdtm..."
pdtm -i subfinder -no-prompt 2>/dev/null || true

info "Installing httpx via pdtm..."
pdtm -i httpx -no-prompt 2>/dev/null || true

# install anew 
if ! command -v anew &>/dev/null; then
    info "Installing anew..."
    go install -v github.com/tomnomnom/anew@latest
fi
success "anew installed: $(which anew)"


echo ""
info "Verifying tools..."
for tool in subfinder httpx anew; do
    if command -v "$tool" &>/dev/null; then
        success "$tool: $(which $tool)"
    else
        warn "$tool NOT FOUND — add $(go env GOPATH)/bin to your PATH and retry"
    fi
done

# set recon-auto.sh executable
if [[ -f scripts/recon-auto.sh ]]; then
    chmod +x scripts/recon-auto.sh
    success "scripts/recon-auto.sh is now executable"
fi

echo -e "\n${GREEN}✔ Setup complete! Run: bash scripts/recon-auto.sh${RESET}\n"
