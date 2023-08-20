# Generate Entity-Relationship Diagrams for Rails applications
# https://github.com/voormedia/rails-erd
erd:
	bundle exec erd && mv erd.pdf ./notes

yard:
	yard doc --protected --private lib/**/*.rb app/**/*.rb

start-debug:
	rdbg --nonstop --open -c -- bin/rails server -p 3050
