class_name BuildId
extends RefCounted
## Which build is running, for result lines (bench "build="). The deploy
## workflow writes the commit here before exporting; local builds say "dev".
const ID := "dev"
