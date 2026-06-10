# keychain — Makefile for building keychain.pyz (single-file Python executable)
#
# Prerequisites: Python 3.9+ on the build host. No other dependencies needed.
#
# Targets:
#   make keychain.pyz   — build the zipapp
#   make clean          — remove build artifacts

V := $(shell cat VERSION)

.PHONY : all clean keychain.pyz release-artifacts

all : keychain.pyz

src/keychain/docs/_doc_texts.json : man/embedded-docs.txt scripts/build_doc_texts.py
	python3 scripts/build_doc_texts.py

keychain.pyz : Makefile $(shell find src/keychain -name '*.py') src/keychain/docs/_doc_texts.json man/embedded-docs.txt scripts/build_doc_texts.py VERSION scripts/pyz_bootstrap.py
	rm -rf build/pyz-stage
	mkdir -p build/pyz-stage
	cp -r src/keychain build/pyz-stage/
	cp VERSION build/pyz-stage/keychain/VERSION
	find build/pyz-stage -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
	python3 -m compileall -q build/pyz-stage
	cp scripts/pyz_bootstrap.py build/pyz-stage/__main__.py
	python3 -m zipapp build/pyz-stage -o keychain.pyz -p '/usr/bin/env python3' -c
	chmod +x keychain.pyz

dist :
	mkdir -p dist

dist/keychain-$(V).pyz : keychain.pyz | dist
	cp keychain.pyz dist/keychain-$(V).pyz

dist/SHA256SUMS : dist/keychain-$(V).pyz
	cd dist && sha256sum keychain-$(V).pyz > SHA256SUMS

release-artifacts : dist/keychain-$(V).pyz dist/SHA256SUMS
	cd dist && sha256sum -c SHA256SUMS

clean :
	rm -rf dist build keychain.pyz src/keychain/docs/_doc_texts.json
	find src -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
