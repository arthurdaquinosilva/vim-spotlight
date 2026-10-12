VIM  ?= vim
NVIM ?= nvim
VINT ?= vint

.PHONY: test test-vim test-nvim lint

test: test-vim test-nvim

test-vim:
	@rm -f test/results-vim.tap; SPOTLIGHT_TEST_LOG=test/results-vim.tap $(VIM) -Nu NONE -i NONE -n --not-a-term \
		-S test/run.vim </dev/null >/dev/null 2>&1; status=$$?; \
		cat test/results-vim.tap 2>/dev/null || echo "no report: editor exited early"; exit $$status

test-nvim:
	@rm -f test/results-nvim.tap; SPOTLIGHT_TEST_LOG=test/results-nvim.tap $(NVIM) --clean --headless \
		-S test/run.vim </dev/null >/dev/null 2>&1; status=$$?; \
		cat test/results-nvim.tap 2>/dev/null || echo "no report: editor exited early"; exit $$status

lint:
	$(VINT) --enable-neovim plugin autoload
