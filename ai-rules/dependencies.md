# Dependency Injection Pattern

Use the `Factory` pattern to create factory classes responsible for setting up objects.

The factory class should be the only source that knows how to compose dependencies together—it acts as the composition root.

You can use the same factory inside the `makeSUT` method of unit tests to create the SUT instance, so you test the same composition as the production code. However, this is not always necessary or desirable in unit tests.

See `NetworkCoverageFactory` for an example of how such a factory looks.
