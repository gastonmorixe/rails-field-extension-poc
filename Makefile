# Generate Entity-Relationship Diagrams for Rails applications
# https://github.com/voormedia/rails-erd
erd: 
	bundle exec erd && mv erd.pdf ./notes
