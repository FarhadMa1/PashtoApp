/// Fisher-Yates. Every permutation of distinct values is equally likely.
func shuffled<T>(
    _ values: [T],
    using rng: inout some RandomNumberGenerator
) -> [T] {
    var copy = values
    guard copy.count > 1 else { return copy }
    var index = copy.count - 1
    while index > 0 {
        let choice = Int(rng.next() % UInt64(index + 1))
        copy.swapAt(index, choice)
        index -= 1
    }
    return copy
}

/// One Fisher-Yates draw. When that draw is rejected, another Fisher-Yates
/// draw picks uniformly from the permutations `isAllowed` accepts.
///
/// Nil when none are accepted. More than eight values are not enumerated: a
/// rejected first draw returns nil, which keeps a long token list from walking
/// every arrangement.
func shuffledUntil<T>(
    _ values: [T],
    using rng: inout some RandomNumberGenerator,
    isAllowed: ([T]) -> Bool
) -> [T]? {
    let draw = shuffled(values, using: &rng)
    if isAllowed(draw) {
        return draw
    }
    guard values.count <= 8 else { return nil }
    let allowed = permutations(of: values).filter(isAllowed)
    guard !allowed.isEmpty else { return nil }
    if allowed.count == 1 {
        return allowed[0]
    }
    return shuffled(allowed, using: &rng)[0]
}

/// Fisher-Yates order that is not `values`, when another order exists.
func shuffledDifferent<T: Equatable>(
    _ values: [T],
    using rng: inout some RandomNumberGenerator
) -> [T] {
    guard values.count > 1 else { return values }
    var differs = false
    for value in values.dropFirst() where value != values[0] {
        differs = true
        break
    }
    guard differs else { return values }
    return shuffledUntil(values, using: &rng) { $0 != values } ?? values
}

private func permutations<T>(of values: [T]) -> [[T]] {
    guard values.count > 1 else { return [values] }
    var copy = values
    var result: [[T]] = []
    func walk(_ start: Int) {
        if start == copy.count {
            result.append(copy)
            return
        }
        var index = start
        while index < copy.count {
            copy.swapAt(start, index)
            walk(start + 1)
            copy.swapAt(start, index)
            index += 1
        }
    }
    walk(0)
    return result
}
