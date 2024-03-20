enum Type {
  Bool = "bool",
}

type Argument = {
  name: string;
  default?: string | number;
  description: string;
  required?: boolean;
  type?: Type;
};

type Group = {
  name: string;
  description: string;
  arguments: Array<Argument>;
};

type Command = {
  name: string;
  groups: Array<Group>;
};

export type { Command, Group, Argument };
export { Type };
