#!/usr/bin/env bash
# Creates App/AnghkooeyTests/Fixtures/sample.apkg for import tests.
# Requires: sqlite3, zip (both available on macOS by default).
# Run once from the repo root: bash scripts/create_anki_fixture.sh
set -euo pipefail

FIXTURES_DIR="App/AnghkooeyTests/Fixtures"
mkdir -p "$FIXTURES_DIR"

TMPDIR_PATH=$(mktemp -d)
DB="$TMPDIR_PATH/collection.anki2"
trap "rm -rf $TMPDIR_PATH" EXIT

# col.crt = 1700000000 (Unix timestamp ~Nov 2023, used as collection epoch)
MODELS='{"1000000001":{"id":1000000001,"name":"Basic","type":0,"flds":[{"name":"Front","ord":0},{"name":"Back","ord":1}],"tmpls":[{"name":"Card 1"}]},"1000000002":{"id":1000000002,"name":"Cloze","type":1,"flds":[{"name":"Text","ord":0}],"tmpls":[{"name":"Cloze"}]}}'
DECKS='{"1":{"id":1,"name":"Default"},"2":{"id":2,"name":"Medical::Anatomy"}}'

sqlite3 "$DB" <<SQL
CREATE TABLE col(id INTEGER PRIMARY KEY,crt INTEGER,mod INTEGER,scm INTEGER,ver INTEGER,dty INTEGER,usn INTEGER,ls INTEGER,conf TEXT,models TEXT,decks TEXT,dconf TEXT,tags TEXT);
CREATE TABLE notes(id INTEGER PRIMARY KEY,guid TEXT NOT NULL,mid INTEGER NOT NULL,mod INTEGER NOT NULL,usn INTEGER NOT NULL,tags TEXT NOT NULL,flds TEXT NOT NULL,sfld TEXT NOT NULL,csum INTEGER NOT NULL,flags INTEGER NOT NULL,data TEXT NOT NULL);
CREATE TABLE cards(id INTEGER PRIMARY KEY,nid INTEGER NOT NULL,did INTEGER NOT NULL,ord INTEGER NOT NULL,mod INTEGER NOT NULL,usn INTEGER NOT NULL,type INTEGER NOT NULL,queue INTEGER NOT NULL,due INTEGER NOT NULL,ivl INTEGER NOT NULL,factor INTEGER NOT NULL,reps INTEGER NOT NULL,lapses INTEGER NOT NULL,left INTEGER NOT NULL,odue INTEGER NOT NULL,odid INTEGER NOT NULL,flags INTEGER NOT NULL,data TEXT NOT NULL);
INSERT INTO col VALUES(1,1700000000,0,0,11,0,0,0,'{}','$MODELS','$DECKS','{}','{}');
-- note 1001: Basic, Default deck, review card (type=2), due=100 days after crt
INSERT INTO notes VALUES(1001,'g1',1000000001,0,0,'','What is ATP?'||char(31)||'Adenosine triphosphate','What is ATP?',0,0,'');
INSERT INTO cards VALUES(2001,1001,1,0,0,0,2,2,100,10,2500,5,0,0,0,0,0,'');
-- note 1002: Basic, HTML + audio token, new card (type=0)
INSERT INTO notes VALUES(1002,'g2',1000000001,0,0,'','&lt;b&gt;Mitosis&lt;/b&gt; result?'||char(31)||'Two cells [sound:beep.mp3]','Mitosis',0,0,'');
INSERT INTO cards VALUES(2002,1002,1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,'');
-- note 1003: Cloze (should be skipped)
INSERT INTO notes VALUES(1003,'g3',1000000002,0,0,'','{{c1::Paris}} is capital','',0,0,'');
INSERT INTO cards VALUES(2003,1003,1,0,0,0,2,2,200,20,2500,3,0,0,0,0,0,'');
-- note 1004: Basic, Medical::Anatomy deck (nested deck → split tags)
INSERT INTO notes VALUES(1004,'g4',1000000001,0,0,'','Q in anatomy deck'||char(31)||'A in anatomy deck','Q',0,0,'');
INSERT INTO cards VALUES(2004,1004,2,0,0,0,2,2,50,7,2500,2,0,0,0,0,0,'');
SQL

(cd "$TMPDIR_PATH" && zip -q sample.apkg collection.anki2)
cp "$TMPDIR_PATH/sample.apkg" "$FIXTURES_DIR/sample.apkg"
echo "Created $FIXTURES_DIR/sample.apkg ($(wc -c < $FIXTURES_DIR/sample.apkg | tr -d ' ') bytes)"
