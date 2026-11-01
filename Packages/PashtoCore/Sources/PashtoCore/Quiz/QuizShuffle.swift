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
