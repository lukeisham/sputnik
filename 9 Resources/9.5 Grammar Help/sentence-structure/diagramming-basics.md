# Sentence Diagramming Basics

Sentence diagramming is a visual method for parsing grammatical structure. It places the subject and verb on a horizontal baseline, with modifiers, objects, and phrases branching below.

## Simple Sentence

> *Birds sing.*

```
   Birds   |   sing
-----------|----------
```

- Subject on the left, verb on the right, separated by a vertical line.

## With Direct Object

> *Birds sing songs.*

```
   Birds   |   sing   |   songs
-----------|----------|---------
```

- Direct object follows a shorter vertical line after the verb.

## With Adjectives and Adverbs

> *Small birds sing sweetly.*

```
   birds   |   sing
-----------|----------
  \small   |   \sweetly
```

- Modifiers hang on diagonal lines below what they modify.

## With Prepositional Phrase

> *Birds sing in the trees.*

```
   Birds   |   sing
-----------|----------
           |     \ in
           |        \ trees
           |           \ the
```

## Compound Elements

> *Birds and frogs sing and chirp.*

```
           |   sing
   Birds   |----------
-----------|   chirp
     \and  |
   frogs   |
```

## Complex Sentence

> *When it rains, birds sing.*

```
   birds   |   sing
-----------|----------
           |   \ When
           |       \ rains
           |           \ it
```

## Limitations

Diagramming works best for classical analysis. For deep syntactic parsing (e.g., distinguishing complement types, handling ellipsis), modern parse trees provide more precision. Diagramming is most useful as a teaching tool and for quick structural check of sentences under ~25 words.

✅ Diagram a sentence to spot missing subjects, dangling modifiers, or unclear antecedents.
✅ Use it as a drafting check — if the diagram looks tangled, the sentence probably is too.
