/// Where the saved text came from. Old history has no such evidence.
enum CommandOrigin { own, screen, unknown }

typedef TrackedCommand = ({String text, CommandOrigin origin});
