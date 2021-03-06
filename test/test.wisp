(test "wisp tests"

  ("control - this test should fail" #f)

  ("map"
    (= (map inc '(1 2 3)) '(2 3 4)))

  ("fold"
    (= (fold (flip cons) '() '(1 2 3 4 5)) '(5 4 3 2 1)))

  ("filter"
    (= (filter number? '(1 2 'a "wat" (make-ref))) '(1 2)))

  ("currying"
    (let ((ap (fn (op a b) (op a b))))
      (and (= (+ 1 2) (((ap +) 1) 2))
           (= "abc" ((ap str) "a" "bc"))
           (= '(a (b c)) (((ap list) 'a) '(b c))))))

  ("let, currying, and scoping"
    (let ((a 1) (b 2) (c 3) (add3 (fn (c d e) (+ c d e))))
      (and (= a 1)
           (= b 2)
           (= c 3)
           (= 6 (add3 a b c))
           (= 6 (((add3 a) b) c)))))

  ("type predicates"
   (and (list? '(1))
        (number? 72165972.451)
        (string? "no way bro")
        (symbol? 'hahawow)
        (bool? #f)
        (ref? (make-ref))
        (ref? (make-self-ref))
        (not (string? 'wat))
        (not (list? "glug"))
        (not (primitive? list))
        (primitive? +)
        (not (number? "pew pew pew"))))

  ("destructuring"
   (let (((a (b c) & d) '(1 (2 3) 4 5 6)))
     (and (= 1 a)
          (= 2 b)
          (= 3 c)
          (= '(4 5 6) d))))

  ("destructuring with currying"
   (let ((f (fn (a (b & c)) (list a b c))))
     (= '(1 2 (3)) ((f 1) '(2 3))))))

