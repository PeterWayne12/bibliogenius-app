class CuratedBook {
  final String title;
  final String author;
  final String? isbn;
  final String? coverUrl;

  const CuratedBook({
    required this.title,
    required this.author,
    this.isbn,
    this.coverUrl,
  });
}

class CuratedList {
  final String title;
  final String description;
  final List<CuratedBook> books;
  final String? coverUrl;

  const CuratedList({
    required this.title,
    required this.description,
    required this.books,
    this.coverUrl,
  });
}

/// How to add a new curated list:
/// 1. Create a new `CuratedList` object in the `curatedLists` array below.
/// 2. Provide a `title` and `description` (in French preferred).
/// 3. Add a `coverUrl` (optional) for the list cover.
/// 4. Populate `books` with `CuratedBook` entries. Use ISBN-13 whenever possible to ensure accurate metadata.
///
/// Example:
/// ```dart
/// CuratedList(
///   title: "My New List",
///   description: "A description of this amazing collection.",
///   books: [
///     CuratedBook(title: "Book Title", author: "Author", isbn: "978..."),
///   ],
/// )
/// ```
const List<CuratedList> curatedLists = [
  CuratedList(
    title: "Les 100 livres du siècle (Le Monde)",
    description:
        "Les 100 meilleurs livres du 20ème siècle, selon un sondage réalisé au printemps 1999 par la Fnac et le journal Le Monde.",
    coverUrl: "https://covers.openlibrary.org/b/id/10520666-L.jpg",
    books: [
      CuratedBook(
        title: "The Stranger",
        author: "Albert Camus",
        isbn: "9780679720201",
      ),
      CuratedBook(
        title: "In Search of Lost Time",
        author: "Marcel Proust",
        isbn: "9780679729686",
      ),
      CuratedBook(
        title: "The Trial",
        author: "Franz Kafka",
        isbn: "9780805209990",
      ),
      CuratedBook(
        title: "The Little Prince",
        author: "Antoine de Saint-Exupéry",
        isbn: "9780156012195",
      ),
      CuratedBook(
        title: "The Human Condition",
        author: "André Malraux",
        isbn: "9780679725756",
      ),
      CuratedBook(
        title: "Journey to the End of the Night",
        author: "Louis-Ferdinand Céline",
        isbn: "9780811216548",
      ),
      CuratedBook(
        title: "The Grapes of Wrath",
        author: "John Steinbeck",
        isbn: "9780143039433",
      ),
      CuratedBook(
        title: "For Whom the Bell Tolls",
        author: "Ernest Hemingway",
        isbn: "9780684803357",
      ),
      CuratedBook(
        title: "The Great Gatsby",
        author: "F. Scott Fitzgerald",
        isbn: "9780743273565",
      ),
      CuratedBook(
        title: "Nineteen Eighty-Four",
        author: "George Orwell",
        isbn: "9780451524935",
      ),
    ],
  ),
  CuratedList(
    title: "Prix Hugo (Meilleur Roman)",
    description:
        "Romans de science-fiction et de fantasy ayant remporté le prestigieux prix Hugo.",
    coverUrl: "https://covers.openlibrary.org/b/id/8259443-L.jpg",
    books: [
      CuratedBook(
        title: "Dune",
        author: "Frank Herbert",
        isbn: "9780441172719",
      ),
      CuratedBook(
        title: "The Left Hand of Darkness",
        author: "Ursula K. Le Guin",
        isbn: "9780441478125",
      ),
      CuratedBook(
        title: "Neuromancer",
        author: "William Gibson",
        isbn: "9780441569595",
      ),
      CuratedBook(
        title: "Ender's Game",
        author: "Orson Scott Card",
        isbn: "9780812550702",
      ),
      CuratedBook(
        title: "Hyperion",
        author: "Dan Simmons",
        isbn: "9780553283686",
      ),
      CuratedBook(
        title: "American Gods",
        author: "Neil Gaiman",
        isbn: "9780380789030",
      ),
      CuratedBook(
        title: "The Three-Body Problem",
        author: "Cixin Liu",
        isbn: "9780765377067",
      ),
      CuratedBook(
        title: "The Fifth Season",
        author: "N.K. Jemisin",
        isbn: "9780316229296",
      ),
    ],
  ),
  CuratedList(
    title: "Classiques du Cyberpunk",
    description:
        "High tech, low life. Les textes fondateurs du genre cyberpunk.",
    coverUrl: "https://covers.openlibrary.org/b/id/12556533-L.jpg",
    books: [
      CuratedBook(
        title: "Neuromancer",
        author: "William Gibson",
        isbn: "9780441569595",
      ),
      CuratedBook(
        title: "Snow Crash",
        author: "Neal Stephenson",
        isbn: "9780553380958",
      ),
      CuratedBook(
        title: "Do Androids Dream of Electric Sheep?",
        author: "Philip K. Dick",
        isbn: "9780345404473",
      ),
      CuratedBook(
        title: "Altered Carbon",
        author: "Richard K. Morgan",
        isbn: "9780345457684",
      ),
    ],
  ),
];
