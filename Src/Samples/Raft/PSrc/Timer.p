//Functions for interacting with the timer machine
fun CreateTimer(owner : machine): machine {
	var m: machine;
	m = new Timer(owner);
	return m;
}

fun StartTimer(timer : machine, time: int) {
	send timer, START, time;
}

fun CancelTimer(timer : machine) {
	send timer, CANCEL;
  receive {
    case CANCEL_SUCCESS: (payload: machine){}
    case CANCEL_FAILURE: (payload: machine) { 
      receive {
        case TIMEOUT: (payload: machine) {}
      }
    }
  }
}


machine Timer {
  var client: machine;

  start state Init {
    entry (payload: machine) {
      client = payload;
      goto WaitForReq;
    }
  }

  state WaitForReq {
    on CANCEL goto WaitForReq with { 
      send client, CANCEL_FAILURE, this;
    } 
    on START goto WaitForCancel;
  }

  state WaitForCancel {
    ignore START;
    on null goto WaitForReq with { 
	  send client, TIMEOUT, this; 
	}
    on CANCEL goto WaitForReq with {
      if ($) {
        send client, CANCEL_SUCCESS, this;
      } else {
        send client, CANCEL_FAILURE, this;
        send client, TIMEOUT, this;
      }
    }
  }
}
