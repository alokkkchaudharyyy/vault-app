import 'package:flutter_test/flutter_test.dart';
import 'package:vault_app/collections.dart';

void main() {
  test('guesses the collection from the text', () {
    expect(guessCollection('Hidden gem cafe in Goa, must visit! #goa'), Collection.places);
    expect(guessCollection('High protein paneer recipe: 2 tbsp curd, 1 tsp masala'), Collection.recipes);
    expect(guessCollection('New season of this series is on Netflix'), Collection.watchlist);
    expect(guessCollection('These sneakers are ₹1,999 on Myntra'), Collection.wishlist);
    expect(guessCollection('DSA roadmap: how to crack the interview'), Collection.learn);
    expect(guessCollection('lol'), Collection.saved);
  });

  test('a Maps screenshot is a place whatever it says', () {
    expect(guessCollection('Some Shop', app: 'Maps'), Collection.places);
  });

  test('the saved text names its collection and source', () {
    expect(
      savedBody(Collection.places, 'Cafe Bodega, Goa', source: 'from Instagram, 22 Oct 10:15'),
      'Saved to Places (from Instagram, 22 Oct 10:15):\nCafe Bodega, Goa',
    );
    expect(savedBody(Collection.saved, 'x'), 'Saved to Saved:\nx');
  });
}
