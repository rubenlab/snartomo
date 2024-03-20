import type { Argument, Command, Group } from "./model";

function parseCommand(help: string, name: string): Command {
  const cmd = { name, groups: [] } as Command;
  const arr = help.split("\n");
  let currGrp;
  for (let i = 0; i < arr.length; i++) {
    let content = arr[i];
    content = content.trim();
    if (content === "") {
      continue;
    }
    if (content.startsWith("--")) {
      let description, type, dft;
      const name = content.substring(2);
      {
        i++;
        description = arr[i];
        description = description.trim();
        description = description.substring(13);
      }
      {
        i++;
        type = arr[i];
        type = type.trim();
        type = type.substring(6);
        type = type.toLowerCase();
      }
      {
        i++;
        dft = arr[i];
        dft = dft.trim();
        dft = dft.substring(9);
      }
      const param = {
        name,
        default: dft,
        description,
        type,
      } as Argument;
      currGrp?.arguments.push(param);
    } else {
      if (currGrp != null) {
        cmd.groups.push(currGrp);
      }
      const description = arr[i + 1].trim();
      currGrp = {
        name: content,
        description: description,
        arguments: [],
      } as Group;
      i++; // skip the next group description line
    }
  }
  if (currGrp != null) {
    cmd.groups.push(currGrp);
  }
  return cmd;
}

export default parseCommand;
