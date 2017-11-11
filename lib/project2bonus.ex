defmodule AgentProcess do
  def start_link(neighbor, count, pidAtom) do
    Agent.start_link(fn -> [neighbor] ++ [count]  end, name: pidAtom) 
    Agent.get(pidAtom, &(&1))
  end
end

#The genserver keeps track of the updated list after removing the killed nodes 
defmodule Server do
  use GenServer

  def start_link(k) do
    GenServer.start_link(__MODULE__, k, name: :gens) 
  end

  def init(k) do
    {:ok, k}
  end

  def handle_call(:msg, _from, zeroes) do
    {:reply, zeroes, zeroes}
  end
end

defmodule MainServer do
  def main(args) do
    args |> parse_args  
  end
    
  defp parse_args([]) do
    IO.puts "No arguments given. Enter the value of k again"
  end

  defp parse_args(args) do
    {_, topology, _} = OptionParser.parse(args)                  
        list =[]
        top = Enum.at(topology,1)
        if top == "line" || top == "full" || top == "2D" || top == "imp2D" do
            MainServer.spawnThreadsServer(0, 10, self(), list, topology) 
            keepAlive
        else
            IO.puts "Wrong topology!"
        end
  end

  def keepAlive do
    keepAlive
  end

  def spawnThreadsServer(count, intx, pid, list, topology) do
    algorithm = Enum.at(topology, 2) 
    top = Enum.at(topology, 1)
    numNodes = String.to_integer(Enum.at(topology, 0))
    nodesToKill = String.to_integer(Enum.at(topology, 3))
    
    if count == numNodes do
      killNodes(nodesToKill, list)
      startTime = :os.system_time(:millisecond)

      #The call to the GenServer returns the updated list stored as the state of the GenServer
      newList = GenServer.call(:gens, :msg)

      cond do
       top === "full"  -> createFull(list, 0, startTime, numNodes, algorithm, newList)
       (top === "2D") || (top === "imp2D") -> power = :math.pow(trunc(Float.ceil(:math.sqrt(numNodes))),2);
                                                      spawnMoreProcessesForGrid(length(list), list, power, startTime, algorithm,top, numNodes, newList)
       top == "line" -> createLine(list, 0, startTime, numNodes, algorithm, newList)        
       true -> IO.puts "Wrong algorithm"
      end
    else 
      pid = spawn(MainServer, :someFunction, [])
      list = list ++ [pid]
      processName = "Process" <> Integer.to_string(count)
      spawnThreadsServer(count + 1, intx, pid, list, topology)
    end
  end

  #This function kills the required number of processes which is passed as 'nodesToKill'
  #These processes are removed from the list and the new list is initialized as the state of the GenServer
  def killNodes(nodesToKill, list) do
   if (nodesToKill > 0) do
    pid = Enum.random(list)
    IO.inspect "Killed node: "
    IO.inspect pid 
    list = list -- [pid]
    Process.exit(pid, :kill)
    killNodes(nodesToKill - 1, list)
  end
  Server.start_link(list)
 end

  def someFunction do
    receive do
      {pid, gossip, temp, startTime, numNodes, list} ->  pidName = List.to_atom(:erlang.pid_to_list(pid))
                                                         IO.inspect "Infecting ";
                                                         IO.inspect "Sleeping";
                                                         send(pid, gossip);
                                                         Process.sleep(1000)
                                                         sendGossip(pid, temp, startTime, numNodes, list);
                                                         someFunction;

      {pid, sends, sendw} -> pidName = List.to_atom(:erlang.pid_to_list(pid)) ;  
                             current = Agent.get(pidName, fn state -> List.last(state) end);
                             newS = elem(current, 0) + sends;
                             newW = elem(current, 1) + sendw;
                             noOfRounds = elem(current, 2);
                             Agent.update(pidName, fn state -> List.replace_at(state, length(state) - 1, {newS, newW, noOfRounds}) end);
                             someFunction
    end
  end

  #After each topology is created, the function sendGossip or sendSW is called with the updated list as parameter
  def createLine(list, index, startTime, numNodes, algorithm, newList) do  
  if index < length(list) do
     if(index == 0) do
        pid = Enum.at(list,0) 
        neighbor = Enum.at(list,1) 
        pidName = List.to_atom(:erlang.pid_to_list(pid))
        neighbors = {neighbor}
      end  
      if(index == length(list) - 1) do
        pid = Enum.at(list,length(list) - 1) 
        neighbor = Enum.at(list,length(list) - 2) 
        pidName = List.to_atom(:erlang.pid_to_list(pid))
        neighbors = {neighbor}
      end
      if(index > 0 && index < length(list) - 1) do
        pid = Enum.at(list, index)
        neighbor1 = Enum.at(list,index - 1)
        neighbor2 = Enum.at(list,index + 1)
        pidName = List.to_atom(:erlang.pid_to_list(pid))
        neighbors = {neighbor1, neighbor2}
      end
       cond do
        algorithm == "gossip" -> AgentProcess.start_link(neighbors,0, pidName)
        algorithm == "push-sum" -> AgentProcess.start_link(neighbors,{index+1, 1, 0}, pidName)
        true-> IO.inspect "Wrong algorithm!"
        end
      createLine(list, index + 1, startTime, numNodes, algorithm, newList) 
  else
    pid = Enum.random(list)
     cond do
        algorithm == "gossip" -> send(pid, {pid, "gossip", 0, startTime, numNodes, list});
                                 sendGossip(pid,0,startTime, numNodes,newList)
        algorithm == "push-sum" -> sendSW(newList, pid,0,startTime, numNodes, 0)
        true-> IO.inspect "Wrong algorithm!"
     end 
  end
 end

def createFull(list, index, startTime, numNodes, algorithm, newList) do  
  if index < length(list) do
        pid = Enum.at(list,index)
        temp = list -- [pid]
        temp = List.to_tuple(temp)
        pidName = List.to_atom(:erlang.pid_to_list(pid))
        cond do
        algorithm == "gossip" -> AgentProcess.start_link(temp,0, pidName)
        algorithm == "push-sum" -> AgentProcess.start_link(temp,{index+1, 1, 0}, pidName)
        true-> IO.inspect "Wrong algorithm!"
        end
      createFull(list, index + 1, startTime, numNodes, algorithm, newList) 
  end
  pid = Enum.random(list)
  IO.inspect "Selected pid: "
  IO.inspect pid
  cond do 
  algorithm == "gossip" -> send(pid, {pid, "gossip"});
                           sendGossip(pid,0,startTime, numNodes,newList);
  algorithm == "push-sum" -> sendSW(newList, pid,0,startTime, numNodes, 0)
  end
 end

def createGrid(list, index, startTime, power, i, j, mapMatrix, algorithm, top1,  numNodes, newList) do  
  pow = :math.sqrt(power)
  if(index == length(list)) do
    getGridNeighbours(list, 0, startTime, power, mapMatrix, algorithm,top1, numNodes, newList)
  end
  pid = Enum.at(list, index) 

  cond do
    index < pow ->  mapMatrix = Map.put(mapMatrix, {i,j}, pid);
                    pidName = List.to_atom(:erlang.pid_to_list(pid))
                    if (algorithm == "gossip") do AgentProcess.start_link({},{i,j}, pidName) end
                    if (algorithm == "push-sum") do AgentProcess.start_link({},[{i,j},{index + 1, 1, 0}], pidName) end
                    j = j + 1;
    (index >= pow && index <= length(list) - 1) -> if (rem(index,trunc(pow)) == 0) do 
                                                      j = 0
                                                      i = i + 1
                                                      pidName = List.to_atom(:erlang.pid_to_list(pid))
                                                      mapMatrix = Map.put(mapMatrix, {i,j}, pid);
                                                      if (algorithm == "gossip") do AgentProcess.start_link({},{i,j}, pidName) end
                                                      if (algorithm == "push-sum") do AgentProcess.start_link({},[{i,j},{index + 1, 1, 0}], pidName) end
                                                   else
                                                      j = j + 1
                                                      pidName = List.to_atom(:erlang.pid_to_list(pid))
                                                      mapMatrix = Map.put(mapMatrix, {i,j}, pid);
                                                      if (algorithm == "gossip") do AgentProcess.start_link({},{i,j}, pidName) end
                                                      if (algorithm == "push-sum") do AgentProcess.start_link({},[{i,j},{index + 1, 1, 0}], pidName) end
                                                   end
    true -> 
  end
  createGrid(list, index + 1, startTime, power, i, j, mapMatrix, algorithm, top1, numNodes, newList)
end

def getGridNeighbours(list, index, startTime, power, mapMatrix, algorithm, top1, numNodes, newList) do
    if(index <= length(list)-1) do
      pid = Enum.at(list,index)
      pidName = List.to_atom(:erlang.pid_to_list(pid))  
      if(algorithm  == "push-sum") do actorRowColumn = Agent.get(pidName, fn state -> List.first(List.last(state)) end) end
      if(algorithm == "gossip") do actorRowColumn = Agent.get(pidName, fn state -> List.last(state) end) end
      row = elem(actorRowColumn, 0) 
      column = elem(actorRowColumn, 1)
      neighbor1 = Map.get(mapMatrix, {row, column+1})
      neighbor2 = Map.get(mapMatrix, {row, column-1})
      neighbor3 = Map.get(mapMatrix, {row-1, column})
      neighbor4 = Map.get(mapMatrix, {row+1, column})
      neighbors = {}

      if(neighbor1 != nil) do neighbors = Tuple.append(neighbors, neighbor1) end
      if(neighbor2 != nil) do neighbors = Tuple.append(neighbors, neighbor2) end
      if(neighbor3 != nil) do neighbors = Tuple.append(neighbors, neighbor3) end
      if(neighbor4 != nil) do neighbors = Tuple.append(neighbors, neighbor4) end

      if(top1 == "imp2D") do
         listValid = list -- Tuple.to_list(neighbors) 
         resultList = listValid -- [pid]
         randomNeighbor = Enum.random(resultList)
         neighbors = Tuple.append(neighbors, randomNeighbor)
      end
      Agent.update(pidName, fn state -> List.replace_at(state, 0, neighbors) end)
      if (algorithm == "gossip") do  Agent.update(pidName, fn state -> List.replace_at(state, 1, 0) end) ;
                                     end
      if (algorithm == "push-sum") do val = Agent.get(pidName, fn state -> List.last(state) end);
                                      val = val --[List.first(val)];
                                      finalVal = List.first(val);
                                      Agent.update(pidName, fn state -> List.replace_at(state, 1, finalVal) end); 
                                    end
      getGridNeighbours(list, index + 1, startTime, power, mapMatrix, algorithm, top1, numNodes, newList)
      else
        IO.inspect "Created neighbors successfully! :)"
        pid = Enum.random(list)
        cond do 
          algorithm == "gossip" -> send(pid, {pid, "gossip"});
                                   pidName = List.to_atom(:erlang.pid_to_list(pid)); 
                                   sendGossip(pid,0,startTime, numNodes, newList);
          algorithm == "push-sum" -> pidName = List.to_atom(:erlang.pid_to_list(pid));
                                     sendSW(newList, pid,0, startTime, numNodes, 0)
        end
    end
end
    
def spawnMoreProcessesForGrid(count, list, power, startTime, algorithm, top, numNodes, newList) do
    if(count == power) do
      i = 0;
      j = 0;
      mapMatrix = %{}
      createGrid(list, 0, startTime, power, i, j, mapMatrix, algorithm, top, numNodes, newList)
    else
      pid = spawn(MainServer, :someFunction, [])
      list = list ++ [pid]
      processName = "Process" <> Integer.to_string(count)
      spawnMoreProcessesForGrid(count + 1, list, power, startTime, algorithm, top, numNodes, newList)
    end
end

 def sendGossip(pid, temp, startTime, numNodes, list) do
     if length(list) == 0 do
       endTime = :os.system_time(:millisecond)
       convergenceTime = endTime - startTime
       IO.puts "Time taken for convergence is: #{convergenceTime} milliseconds"
       Process.exit(self(), :kill)
     end

     pidName = List.to_atom(:erlang.pid_to_list(pid))      
     selectedNeighbor = Agent.get(pidName, fn state -> Enum.random(Tuple.to_list(List.first(state))) end)   
     selectedNeighborName = List.to_atom(:erlang.pid_to_list(selectedNeighbor))   
     
     #Checks whether the selected neighbor is alive
     #If not, the current process is sent back to the function
     if(!Process.alive?(selectedNeighbor)) do
       sendGossip(pid, temp, startTime, numNodes, list)
     end

     count = Agent.get(selectedNeighborName, fn state -> List.last(state) end)  
     
     cond do
        count == 0 -> IO.inspect selectedNeighbor; 
                      IO.inspect "Heard for first time"; 
                      Agent.update(selectedNeighborName, fn state -> List.replace_at(state, length(state) - 1, 1) end);
                      send(selectedNeighbor, {selectedNeighbor, "gossip", temp, startTime, numNodes, list});
                      sendGossip(selectedNeighbor,temp, startTime, numNodes,list)

        count > 0 && count <= 9 -> IO.inspect pid; IO.inspect " sending "; IO.inspect selectedNeighbor;
                                   Agent.update(selectedNeighborName, fn state -> List.replace_at(state, length(state) - 1, List.last(state) + 1) end);
                                   send(selectedNeighbor, {selectedNeighbor, "gossip", temp, startTime, numNodes, list});
                                   sendGossip(selectedNeighbor,temp,startTime, numNodes,list)

        count >= 10 -> IO.inspect pid; 
                       IO.inspect "Heard the gossip 10 times. Can't transmit anymore" ;                
                       list = list -- [pid]
                       sendGossip(selectedNeighbor,temp,startTime, numNodes,list)    
    end
  end

   def sendSW(list, pid,temp,startTime, numNodes, sumCurrentRatio) do
     if length(list) == 0 do
       endTime = :os.system_time(:millisecond)
       convergenceTime = endTime - startTime
       convergenceRatio = sumCurrentRatio / numNodes
       IO.puts "The convergence ratio is: #{convergenceRatio}"
       IO.puts "Time taken for convergence is: #{convergenceTime} milliseconds"
       Process.exit(self(), :kill)
     end

    pidName = List.to_atom(:erlang.pid_to_list(pid))      
    selectedNeighbor = Agent.get(pidName, fn state -> Enum.random(Tuple.to_list(List.first(state))) end)  
    IO.inspect "Selected neighbor is: "
    IO.inspect selectedNeighbor

     #Checks whether the selected neighbor is alive
     #If not, the current process is sent back to the function
     if(!Process.alive?(selectedNeighbor)) do
       IO.inspect "Selected neighbor is not alive"
       sendSW(list, pid, temp, startTime, numNodes, sumCurrentRatio)
     end
    
     noOfRounds = Agent.get(pidName, fn state -> elem(List.last(state),2) end)  
     if(noOfRounds >= 3) do
        IO.inspect pid
        IO.inspect "No. of rounds = 3. Process will now stop transmitting"
        if(Enum.member?(list, pid)) do
            currentRatio = Agent.get(pidName, fn state -> elem(List.last(state),0) end) / Agent.get(pidName, fn state -> elem(List.last(state),1) end)           
            sumCurrentRatio = sumCurrentRatio + currentRatio
        end
        list = list -- [pid]
        sendSW(list, selectedNeighbor, temp, startTime, numNodes, sumCurrentRatio)
     end

     selectedNeighbor = Agent.get(pidName, fn state -> Enum.random(Tuple.to_list(List.first(state))) end)   
     selectedNeighborName = List.to_atom(:erlang.pid_to_list(selectedNeighbor))    
     previousRatio = Agent.get(pidName, fn state -> elem(List.last(state),0) end) / Agent.get(pidName, fn state -> elem(List.last(state),1) end)    
     sends = Agent.get(pidName, fn state -> elem(List.last(state),0)/2 end)  
     sendw = Agent.get(pidName, fn state -> elem(List.last(state),1)/2 end)       
     Agent.update(pidName, fn state -> List.replace_at(state, length(state) - 1, {sends, sendw, noOfRounds}) end)
     currentRatio = Agent.get(pidName, fn state -> elem(List.last(state),0) end) / Agent.get(pidName, fn state -> elem(List.last(state),1) end)           
     
     if(abs(currentRatio-previousRatio) < :math.pow(10,-10)) do
        noOfRounds = noOfRounds + 1
        Agent.update(pidName, fn state -> List.replace_at(state, length(state) - 1, {sends, sendw, noOfRounds}) end)
     else
      Agent.update(pidName, fn state -> List.replace_at(state, length(state) - 1, {sends, sendw, 0}) end)
     end
    
    send(selectedNeighbor, {selectedNeighbor, sends, sendw})
    sendSW(list, selectedNeighbor, temp, startTime, numNodes, sumCurrentRatio)
   end  
end