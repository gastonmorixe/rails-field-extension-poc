# Generate Entity-Relationship Diagrams for Rails applications
# https://github.com/voormedia/rails-erd
erd:
	bundle exec erd && mv erd.pdf ./notes

yard:
	bundle exec yard doc --protected --private --embed-mixins --debug lib/**/*.rb app/**/*.rb

start-debug:
	rdbg --nonstop --open -c -- bin/rails server -p 3050

rubocop-generate:
	bundle exec rubocop \
		--auto-gen-config \
		--auto-gen-only-exclude \
		--no-exclude-limit
