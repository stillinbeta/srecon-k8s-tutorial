.PHONY: lint

all: lint

deps:
	gem install mdl mdspell

lint:
	mdl --git-recurse --style style.rb .
	mdspell -c mdspell.yaml .
