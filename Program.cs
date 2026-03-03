var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => new
{
    title = "Hello Optimisation !",
    message = "L'application a été construite avec succès !"
});

app.MapGet("/health", () => new { status = "up" });

app.Run();

// test
