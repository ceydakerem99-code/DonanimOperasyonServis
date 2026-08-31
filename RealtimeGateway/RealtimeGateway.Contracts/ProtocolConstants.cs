namespace RealtimeGateway.Contracts;

public static class ProtocolVersion
{
    public const int Current = 1;
}

public static class MessageTypes
{
    public const string Hello = "hello";
    public const string HelloOk = "hello.ok";
    public const string OpSubmit = "op.submit";
    public const string OpAck = "op.ack";
    public const string EventApply = "event.apply";
    public const string Ping = "ping";
    public const string Pong = "pong";
    public const string Error = "error";
}

public static class EntityTypes
{
    public const string Customer = "customer";
    public const string WorkOrder = "workOrder";

    public static readonly HashSet<string> Faz1Supported = new(StringComparer.Ordinal)
    {
        Customer,
        WorkOrder
    };
}

public static class OperationTypes
{
    public const string Create = "create";
    public const string Update = "update";
    public const string Delete = "delete";
}

public static class UserRoles
{
    public const string Admin = "admin";
    public const string Operator = "operator";
    public const string Technician = "technician";
    public const string Unknown = "unknown";
}
